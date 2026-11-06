// Supabase Edge Function：pdf-extract
// 作用：接收 PDF 文件（base64），用 pdfjs 提取文字层，返回 { text }。
// 部署：supabase functions deploy pdf-extract
// 调用：POST /functions/v1/pdf-extract ，Header 带 Authorization + apikey。
//
// 环境变量（占位，绝不写真实值）：
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY —— 本函数目前不需要访问数据库，
//   留作以后扩展（如把提取结果记日志）时用；部署时在 Dashboard → Edge Functions
//   → Secrets 里配，不要写进代码。
// 扫描版 PDF（无文字层）返回 422 + 中文错误，App 端据此提示用户转文字版。

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
// pdfjs：Deno 里通过 npm 兼容层引入；按页取文本，思路与刷题 App 的
// PDFKit 文字层读取一致——有文字层直接读，没有就报 422，不做 OCR。
// 注意：pdfjs-dist 需要在部署前确认版本可用；若某版本在 Edge Runtime
// 下跑不起来，可把下行换成等价的轻量解析，或改走 fetch 上游解析服务
// （见下方 fallback 说明），接口（入参/出参/错误码）保持不变。
import * as pdfjs from "npm:pdfjs-dist@4.2.67/legacy/build/pdf.mjs";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "只支持 POST 请求" }, 405);
  }

  let payload: { pdfBase64?: unknown };
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: "请求体不是合法的 JSON" }, 400);
  }
  const pdfBase64 = payload.pdfBase64;
  if (typeof pdfBase64 !== "string" || pdfBase64.length === 0) {
    return jsonResponse({ error: "缺少参数 pdfBase64" }, 400);
  }
  // 限流保护：免费版 Edge Function 单次请求不宜过大，10MB 封顶。
  if (pdfBase64.length > 14_000_000) {
    return jsonResponse({ error: "PDF 文件太大了（超过 10MB），请拆小再传" }, 413);
  }

  let pdfBytes: Uint8Array;
  try {
    const binary = atob(pdfBase64);
    pdfBytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      pdfBytes[i] = binary.charCodeAt(i);
    }
  } catch {
    return jsonResponse({ error: "pdfBase64 解码失败" }, 400);
  }
  // 快速校验：不是 PDF 直接拒掉，不浪费解析时间。
  const header = new TextDecoder().decode(pdfBytes.slice(0, 5));
  if (header !== "%PDF-") {
    return jsonResponse({ error: "这不是一个 PDF 文件" }, 400);
  }

  try {
    const doc = await pdfjs.getDocument({
      data: pdfBytes,
      // Edge Runtime 无 DOM worker，关掉 worker 走主线程解析。
      isEvalSupported: false,
    }).promise;

    const pages: string[] = [];
    for (let i = 1; i <= doc.numPages; i++) {
      const page = await doc.getPage(i);
      const content = await page.getTextContent();
      const line = content.items
        .map((item) => ("str" in item ? item.str : ""))
        .join(" ");
      pages.push(line);
    }
    const text = pages.join("\n").replace(/[ \t]+/g, " ").trim();

    // 提不到文字 = 扫描版（全是图片、无文字层），按约定返回 422。
    if (text.length < 10) {
      return jsonResponse(
        { error: "这是扫描版 PDF，没有文字层，请转文字版 PDF 再导入" },
        422,
      );
    }
    return jsonResponse({ text });
  } catch (e) {
    // pdfjs 抛错分两类：加密/损坏的 PDF 与运行环境问题，都给中文错。
    const message = e instanceof Error ? e.message : "未知错误";
    if (/password|encrypted/i.test(message)) {
      return jsonResponse({ error: "这个 PDF 加了密码，请先解密再导入" }, 422);
    }
    // Fallback 说明：如果 pdfjs 在 Edge Runtime 下持续跑不起来，
    // 可在此处改成 fetch 上游解析服务（例如自建的解析接口）：
    //   const res = await fetch("https://<上游解析地址>/parse", {...})
    // 上游地址与密钥同样走 Deno.env.get("PDF_UPSTREAM_URL") 等环境变量，
    // 绝不写死在代码里；返回体仍保持 { text }，失败仍返回中文 error。
    console.error("pdf-extract failed:", message);
    return jsonResponse({ error: "PDF 文字提取失败，请换个文字版 PDF 再试" }, 500);
  }
});
