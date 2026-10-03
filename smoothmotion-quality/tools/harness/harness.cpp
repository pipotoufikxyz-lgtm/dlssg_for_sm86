// Runs the SmoothMotion synthesis shader (as embedded in new.asi) on D3D11.
// Pass order and resource layout follow the shader's own comments:
// RefineForward/RefineBackward -> Project -> DominantMotion -> OverlayMask ->
// OverlayGrow -> Synthesize (MRT: Reprojection + Choice) -> Coherence -> Resolve.
//
// usage: harness compile <shader.hlsl>
//        harness run <shader.hlsl> <caselist.txt> [norefine]
// caselist lines: <dir> <width> <height>; dir holds prev.raw/cur.raw (RGBA8)
// and fwd.raw/bwd.raw (int16 x2, ceil(w/4) x ceil(h/4)); out.raw is written.
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

typedef HRESULT(WINAPI* CompileFn)(LPCVOID, SIZE_T, LPCSTR, const D3D_SHADER_MACRO*, ID3DInclude*, LPCSTR, LPCSTR, UINT, UINT, ID3DBlob**, ID3DBlob**);

static CompileFn compileFn;
static ID3D11Device* dev;
static ID3D11DeviceContext* ctx;

static std::vector<char> readFile(const char* path) {
  std::vector<char> d; FILE* f = fopen(path, "rb"); if (!f) return d;
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  d.resize(n); fread(d.data(), 1, n, f); fclose(f); return d;
}

static const char* entries[] = {"Fullscreen", "Capture", "Project", "DominantMotion", "Synthesize", "Resolve",
                                "OverlayMask", "OverlayGrow", "Blit", "BlitSrgb", "Coherence", "RefineForward", "RefineBackward"};

static ID3DBlob* compileEntry(const std::vector<char>& src, const char* entry, bool& ok) {
  ID3DBlob *code = nullptr, *err = nullptr;
  const char* profile = strcmp(entry, "Fullscreen") == 0 ? "vs_5_0" : "ps_5_0";
  DWORD t0 = GetTickCount();
  HRESULT hr = compileFn(src.data(), src.size(), "shaders.hlsl", nullptr, nullptr, entry, profile, 0x8800, 0, &code, &err);
  DWORD t1 = GetTickCount();
  printf("compile %-15s hr=0x%08lx %5lu ms%s\n", entry, hr, t1 - t0, err ? " (messages)" : "");
  if (err) { printf("%.*s\n", (int)err->GetBufferSize(), (const char*)err->GetBufferPointer()); err->Release(); }
  ok = ok && SUCCEEDED(hr);
  return code;
}

struct Target {
  ID3D11Texture2D* tex = nullptr; ID3D11ShaderResourceView* srv = nullptr; ID3D11RenderTargetView* rtv = nullptr;
  UINT w = 0, h = 0;
};
static Target makeTarget(UINT w, UINT h, DXGI_FORMAT fmt, const void* init = nullptr, UINT pitch = 0) {
  Target t; t.w = w; t.h = h;
  D3D11_TEXTURE2D_DESC d = {}; d.Width = w; d.Height = h; d.MipLevels = 1; d.ArraySize = 1; d.Format = fmt;
  d.SampleDesc.Count = 1; d.Usage = D3D11_USAGE_DEFAULT; d.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
  D3D11_SUBRESOURCE_DATA s = {init, pitch, 0};
  HRESULT hr = dev->CreateTexture2D(&d, init ? &s : nullptr, &t.tex);
  if (FAILED(hr)) { printf("CreateTexture2D fmt=%d failed 0x%08lx\n", fmt, hr); exit(3); }
  dev->CreateShaderResourceView(t.tex, nullptr, &t.srv);
  dev->CreateRenderTargetView(t.tex, nullptr, &t.rtv);
  return t;
}
static void release(Target& t) { if (t.srv) t.srv->Release(); if (t.rtv) t.rtv->Release(); if (t.tex) t.tex->Release(); t = Target(); }

static std::vector<char> readback(Target& t, UINT bpp) {
  D3D11_TEXTURE2D_DESC d; t.tex->GetDesc(&d);
  d.Usage = D3D11_USAGE_STAGING; d.BindFlags = 0; d.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  ID3D11Texture2D* st; dev->CreateTexture2D(&d, nullptr, &st);
  ctx->CopyResource(st, t.tex);
  D3D11_MAPPED_SUBRESOURCE m; ctx->Map(st, 0, D3D11_MAP_READ, 0, &m);
  std::vector<char> out(t.w * t.h * bpp);
  for (UINT y = 0; y < t.h; ++y) memcpy(out.data() + y * t.w * bpp, (char*)m.pData + y * m.RowPitch, t.w * bpp);
  ctx->Unmap(st, 0); st->Release(); return out;
}

int main(int argc, char** argv) {
  if (argc < 3) { printf("usage\n"); return 2; }
  HMODULE dc = LoadLibraryA("d3dcompiler_47_ms.dll");
  if (!dc) { printf("cannot load d3dcompiler_47_ms.dll\n"); return 2; }
  compileFn = (CompileFn)GetProcAddress(dc, "D3DCompile");
  std::vector<char> src = readFile(argv[2]);
  printf("shader %s: %zu bytes\n", argv[2], src.size());
  // The binary passes the exact length; trailing padding must be harmless.
  bool ok = true;
  ID3DBlob* blobs[13];
  for (int i = 0; i < 13; ++i) blobs[i] = compileEntry(src, entries[i], ok);
  if (!ok) { printf("COMPILE FAILED\n"); return 1; }
  if (strcmp(argv[1], "compile") == 0) { printf("COMPILE OK\n"); return 0; }

  D3D_FEATURE_LEVEL fl = D3D_FEATURE_LEVEL_11_0, got;
  HRESULT hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, &fl, 1, D3D11_SDK_VERSION, &dev, &got, &ctx);
  if (FAILED(hr)) { printf("D3D11CreateDevice failed 0x%08lx\n", hr); return 3; }
  ID3D11VertexShader* vs; dev->CreateVertexShader(blobs[0]->GetBufferPointer(), blobs[0]->GetBufferSize(), nullptr, &vs);
  ID3D11PixelShader* ps[13] = {};
  for (int i = 1; i < 13; ++i) dev->CreatePixelShader(blobs[i]->GetBufferPointer(), blobs[i]->GetBufferSize(), nullptr, &ps[i]);
  enum { CAPTURE = 1, PROJECT, DOMINANT, SYNTH, RESOLVE, OMASK, OGROW, BLIT, BLITSRGB, COHERENCE, RFWD, RBWD };
  D3D11_SAMPLER_DESC sd = {}; sd.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
  sd.AddressU = sd.AddressV = sd.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP; sd.MaxLOD = D3D11_FLOAT32_MAX;
  ID3D11SamplerState* samp; dev->CreateSamplerState(&sd, &samp);
  D3D11_BUFFER_DESC bd = {}; bd.ByteWidth = 32; bd.Usage = D3D11_USAGE_DEFAULT; bd.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
  ID3D11Buffer* cb; dev->CreateBuffer(&bd, nullptr, &cb);
  bool refine = !(argc > 4 && strcmp(argv[4], "norefine") == 0);

  FILE* list = fopen(argv[3], "r");
  char dir[1024]; int W, H;
  while (fscanf(list, "%1023s %d %d", dir, &W, &H) == 3) {
    std::string d = dir;
    auto prev = readFile((d + "/prev.raw").c_str()), cur = readFile((d + "/cur.raw").c_str());
    auto fwd = readFile((d + "/fwd.raw").c_str()), bwd = readFile((d + "/bwd.raw").c_str());
    UINT gw = (W + 3) / 4, gh = (H + 3) / 4;
    Target tPrev = makeTarget(W, H, DXGI_FORMAT_R8G8B8A8_UNORM, prev.data(), W * 4);
    Target tCur = makeTarget(W, H, DXGI_FORMAT_R8G8B8A8_UNORM, cur.data(), W * 4);
    Target tFwd = makeTarget(gw, gh, DXGI_FORMAT_R16G16_SINT, fwd.data(), gw * 4);
    Target tBwd = makeTarget(gw, gh, DXGI_FORMAT_R16G16_SINT, bwd.data(), gw * 4);
    Target tFwdR = makeTarget(gw, gh, DXGI_FORMAT_R16G16_SINT), tBwdR = makeTarget(gw, gh, DXGI_FORMAT_R16G16_SINT);
    Target tProj = makeTarget(gw, gh, DXGI_FORMAT_R32G32B32A32_FLOAT);
    Target tDom = makeTarget((W + 7) / 8, (H + 7) / 8, DXGI_FORMAT_R16G16B16A16_FLOAT);
    Target tORaw = makeTarget(W, H, DXGI_FORMAT_R8_UNORM), tONear = makeTarget(W, H, DXGI_FORMAT_R16G16_FLOAT);
    Target tRep = makeTarget(W, H, DXGI_FORMAT_R16G16B16A16_FLOAT), tChoice = makeTarget(W, H, DXGI_FORMAT_R16G16B16A16_FLOAT);
    Target tCoh = makeTarget(W, H, DXGI_FORMAT_R16G16B16A16_FLOAT), tOut = makeTarget(W, H, DXGI_FORMAT_R8G8B8A8_UNORM);
    float settings[8] = {(float)W, (float)H, 1.0f / W, 1.0f / H, 4.0f, 1.0f / 32, 0, 0};
    ctx->UpdateSubresource(cb, 0, nullptr, settings, 0, 0);
    ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    ctx->IASetInputLayout(nullptr);
    ctx->VSSetShader(vs, nullptr, 0);
    ctx->PSSetConstantBuffers(0, 1, &cb); ctx->VSSetConstantBuffers(0, 1, &cb);
    ctx->PSSetSamplers(0, 1, &samp);
    Target* fwdIn = &tFwd; Target* bwdIn = &tBwd;
    // srvs: t0 prev t1 cur t2 fwd t3 bwd t4 reprojection t5 projected t6 overlayRaw t7 overlayNear t8 dominant t9 choice
    auto pass = [&](int shader, std::vector<Target*> rts, Target* rep, Target* choice) {
      ID3D11ShaderResourceView* null10[10] = {};
      ctx->PSSetShaderResources(0, 10, null10);
      ID3D11RenderTargetView* r[2] = {rts[0]->rtv, rts.size() > 1 ? rts[1]->rtv : nullptr};
      ctx->OMSetRenderTargets((UINT)rts.size(), r, nullptr);
      D3D11_VIEWPORT vp = {0, 0, (float)rts[0]->w, (float)rts[0]->h, 0, 1}; ctx->RSSetViewports(1, &vp);
      ID3D11ShaderResourceView* s[10] = {tPrev.srv, tCur.srv, fwdIn->srv, bwdIn->srv, rep ? rep->srv : nullptr, tProj.srv,
                                         tORaw.srv, tONear.srv, tDom.srv, choice ? choice->srv : nullptr};
      for (auto* t : rts) for (auto& x : s) if (t->srv == x) x = nullptr;
      ctx->PSSetShaderResources(0, 10, s);
      ctx->PSSetShader(ps[shader], nullptr, 0);
      ctx->Draw(3, 0);
      ID3D11RenderTargetView* nr[2] = {}; ctx->OMSetRenderTargets(2, nr, nullptr);
    };
    if (refine) {
      pass(RFWD, {&tFwdR}, nullptr, nullptr); pass(RBWD, {&tBwdR}, nullptr, nullptr);
      fwdIn = &tFwdR; bwdIn = &tBwdR;
    }
    pass(PROJECT, {&tProj}, nullptr, nullptr);
    pass(DOMINANT, {&tDom}, nullptr, nullptr);
    pass(OMASK, {&tORaw}, nullptr, nullptr);
    pass(OGROW, {&tONear}, nullptr, nullptr);
    pass(SYNTH, {&tRep, &tChoice}, nullptr, nullptr);
    pass(COHERENCE, {&tCoh}, &tRep, &tChoice);
    pass(RESOLVE, {&tOut}, &tCoh, nullptr);
    auto out = readback(tOut, 4);
    FILE* f = fopen((d + "/out.raw").c_str(), "wb"); fwrite(out.data(), 1, out.size(), f); fclose(f);
    auto rp = readback(tRep, 8);
    f = fopen((d + "/rep.raw").c_str(), "wb"); fwrite(rp.data(), 1, rp.size(), f); fclose(f);
    auto co = readback(tCoh, 8);
    f = fopen((d + "/coh.raw").c_str(), "wb"); fwrite(co.data(), 1, co.size(), f); fclose(f);
    if (refine) {
      auto rf = readback(tFwdR, 4); f = fopen((d + "/fwdR.raw").c_str(), "wb"); fwrite(rf.data(), 1, rf.size(), f); fclose(f);
      auto rb = readback(tBwdR, 4); f = fopen((d + "/bwdR.raw").c_str(), "wb"); fwrite(rb.data(), 1, rb.size(), f); fclose(f);
    }
    auto dm = readback(tDom, 8);
    f = fopen((d + "/dom.raw").c_str(), "wb"); fwrite(dm.data(), 1, dm.size(), f); fclose(f);
    auto om = readback(tORaw, 1);
    f = fopen((d + "/omask.raw").c_str(), "wb"); fwrite(om.data(), 1, om.size(), f); fclose(f);
    auto ch = readback(tChoice, 8);
    f = fopen((d + "/choice.raw").c_str(), "wb"); fwrite(ch.data(), 1, ch.size(), f); fclose(f);
    printf("ran %s %dx%d\n", dir, W, H);
    Target* all[] = {&tPrev, &tCur, &tFwd, &tBwd, &tFwdR, &tBwdR, &tProj, &tDom, &tORaw, &tONear, &tRep, &tChoice, &tCoh, &tOut};
    for (auto* t : all) release(*t);
  }
  printf("RUN OK\n");
  return 0;
}
