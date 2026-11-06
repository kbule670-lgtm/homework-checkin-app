/// 拍照上传提交页：B 组。
///
/// image_picker 多选拍照 / 相册，张数不限；显示缩略图、可删除；
/// 提交时上传到 Supabase Storage homework-photos 桶，再调提交服务。
/// 未配置 Supabase 时显示中文提示，不闪退。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/models.dart';
import '../../services/submission_service.dart';
import '../../services/supabase_service.dart';
import '../../services/assignment_service.dart';
import '../theme.dart';

class SubmitPhotoScreen extends StatefulWidget {
  final Assignment assignment;

  const SubmitPhotoScreen({super.key, required this.assignment});

  @override
  State<SubmitPhotoScreen> createState() => _SubmitPhotoScreenState();
}

class _SubmitPhotoScreenState extends State<SubmitPhotoScreen> {
  final _submissionService = SubmissionService();
  final _picker = ImagePicker();
  final List<XFile> _photos = [];
  bool _uploading = false;

  Assignment get _assignment => widget.assignment;

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickMultiImage();
      if (picked.isEmpty) return;
      setState(() => _photos.addAll(picked));
    } catch (e) {
      _showMessage('选择照片失败：$e');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final picked =
          await _picker.pickImage(source: ImageSource.camera);
      if (picked == null) return;
      setState(() => _photos.add(picked));
    } catch (e) {
      _showMessage('拍照失败：$e');
    }
  }

  Future<void> _submit() async {
    if (!SupabaseService.isConfigured) {
      _showMessage(kSupabaseNotConfiguredMessage);
      return;
    }
    if (_photos.isEmpty) {
      _showMessage('请先选择或拍摄照片');
      return;
    }
    setState(() => _uploading = true);
    try {
      final uid = SupabaseService.client.auth.currentUser?.id ?? '';
      final urls = <String>[];
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < _photos.length; i++) {
        final bytes = await _photos[i].readAsBytes();
        final path =
            '${_assignment.id}/$uid/${timestamp}_$i.jpg';
        await SupabaseService.client.storage
            .from('homework-photos')
            .uploadBinary(
              path,
              bytes,
              fileOptions:
                  const FileOptions(contentType: 'image/jpeg'),
            );
        final url = SupabaseService.client.storage
            .from('homework-photos')
            .getPublicUrl(path);
        urls.add(url);
      }
      final submission = await _submissionService.submitPhotos(
        assignmentId: _assignment.id,
        photoUrls: urls,
      );
      if (!mounted) return;
      _showMessage(submission.isLate ? '已提交，记为迟交' : '提交成功');
      Navigator.of(context).pop(true);
    } on StateError catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('提交失败：$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!SupabaseService.isConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('拍照上传')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              kSupabaseNotConfiguredMessage,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('拍照上传')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _assignment.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text('已选 ${_photos.length} 张照片，张数不限'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploading ? null : _pickFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('从相册选择'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploading ? null : _takePhoto,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('拍照'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _photos.isEmpty
                ? const Center(child: Text('还没有照片，先选几张吧'))
                : GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _photos.length,
                    itemBuilder: (context, index) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(_photos[index].path),
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: _uploading
                                  ? null
                                  : () {
                                      setState(
                                          () => _photos.removeAt(index));
                                    },
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _uploading ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_uploading ? '上传中…' : '提交作业'),
            ),
          ),
        ],
      ),
    );
  }
}
