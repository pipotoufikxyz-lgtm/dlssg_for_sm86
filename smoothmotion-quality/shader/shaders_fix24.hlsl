
Texture2D<float4> Previous : register(t0);
Texture2D<float4> Current : register(t1);
Texture2D<int2> Forward : register(t2);
Texture2D<int2> Backward : register(t3);
// Private RGBA16F intermediate: RGB is the midpoint, A is confidence plus 2
// for pixels flagged as a static overlay (see overlayFlag). Neither may reach
// the game's backbuffer alpha channel.
Texture2D<float4> Reprojection : register(t4);
// Private RGBA32F grid: two distinct motions crossing each flow cell at t=0.5.
Texture2D<float4> Projected : register(t5);
// Private R8 masks (Fix19): 1 where a pixel is static overlay detail (HUD,
// crosshair; OverlayMask pass), and the same mask grown by two pixels to
// cover antialiased and translucent outlines (OverlayGrow pass).
Texture2D<float> OverlayRaw : register(t6);
Texture2D<float> OverlayNear : register(t7);
SamplerState LinearClamp : register(s0);
// FlowBlock: output pixels per flow cell (4 for full-resolution flow, 8 when
// flow is computed at half resolution). FlowGain converts stored S10.5 flow
// to output pixels (1/32, or 2/32 at half resolution).
cbuffer Settings : register(b0) { float2 ImageSize; float2 InvImageSize; float FlowBlock; float FlowGain; float2 SettingsPad; };
struct Vertex { float4 position : SV_Position; float2 uv : TEXCOORD0; };
Vertex Fullscreen(uint id : SV_VertexID) {
 Vertex v; v.uv=float2((id<<1)&2,id&2);
 v.position=float4(v.uv*float2(2,-2)+float2(-1,1),0,1); return v;
}
float4 Capture(Vertex v) : SV_Target { return Previous.SampleLevel(LinearClamp,v.uv,0); }
// Flow grid coordinates: cell c covers FlowBlock output pixels, centred at
// c*FlowBlock+(FlowBlock-1)/2.
int2 gridMaximum() { return int2(ceil(ImageSize/FlowBlock))-1; }
float2 toGrid(float2 p) { return (p-(FlowBlock-1)*0.5)/FlowBlock; }
float2 cellCenter(int2 c) { return float2(c)*FlowBlock+(FlowBlock-1)*0.5; }
// NVOF signed S10.5 displacement of one block, in output pixels. Cells are
// clamped so any corrupted vector can only select a valid grid location.
float2 cellFlow(int2 c,bool backward) {
 c=clamp(c,int2(0,0),gridMaximum());
 if(backward)return Backward.Load(int3(c,0))*FlowGain;
 return Forward.Load(int3(c,0))*FlowGain;
}
// Bilinear flow at p, the smallest deviation of its four cells from the
// expected motion, and the most different cell. The minimum keeps a boundary
// pixel supported by the object it belongs to, and the most different cell is
// the unmixed occluder; bilinear mixing of foreground and background is neither.
struct Probe { float2 flow; float support; float2 other; float deviation; };
Probe probe(float2 p,float2 expected,bool backward) {
 float2 q=toGrid(p);
 int2 i=int2(floor(q)); float2 t=frac(q);
 float2 va=cellFlow(i,backward), vb=cellFlow(i+int2(1,0),backward);
 float2 vc=cellFlow(i+int2(0,1),backward), vd=cellFlow(i+int2(1,1),backward);
 float da=length(va-expected), db=length(vb-expected);
 float dc=length(vc-expected), dd=length(vd-expected);
 Probe r;
 r.flow=lerp(lerp(va,vb,t.x),lerp(vc,vd,t.x),t.y);
 r.support=min(min(da,db),min(dc,dd));
 r.other=va; r.deviation=da;
 if(db>r.deviation){r.other=vb;r.deviation=db;}
 if(dc>r.deviation){r.other=vc;r.deviation=dc;}
 if(dd>r.deviation){r.other=vd;r.deviation=dd;}
 return r;
}
float2 flowAt(float2 p,bool backward) { return probe(p,float2(0,0),backward).flow; }
// Carry every block vector to the grid cell it crosses at the midpoint. Thin
// objects are found here even when their flow lies several pixels away from
// where they appear, which gathering at the output pixel alone cannot do.
// The nearest crossing and the nearest clearly different crossing are kept.
// Search windows follow the local motion, so fast pans (tens of pixels per
// frame at a 30 FPS base) still reach the sources that cross this cell; the
// window radius (5 cells) covers objects moving up to 10 cells relative to that.
float4 Project(Vertex v) : SV_Target {
 int2 cell=int2(floor(v.position.xy));
 int2 maximum=gridMaximum();
 float2 center=cellCenter(cell);
 float2 hint=0.5*(cellFlow(cell,false)-cellFlow(cell,true));
 int2 offset=int2(floor(hint/(2*FlowBlock)+0.5));
 float2 first=float2(0,0), second=float2(0,0);
 float firstDistance=1e9, secondDistance=1e9;
 [loop] for(int y=-5;y<=5;++y)
  [loop] for(int x=-5;x<=5;++x){
   [unroll] for(int side=0;side<2;++side){
    int2 source=cell+(side==0?int2(0,0)-offset:offset)+int2(x,y);
    if(!all(source>=0)||!all(source<=maximum))continue;
    float2 origin=cellCenter(source);
    float2 m=side==0?cellFlow(source,false):float2(0,0)-cellFlow(source,true);
    float d=length((side==0?origin+0.5*m:origin-0.5*m)-center);
    if(d<firstDistance){
     if(length(m-first)>2){second=first;secondDistance=firstDistance;}
     first=m;firstDistance=d;
    }else if(d<secondDistance&&length(m-first)>2){second=m;secondDistance=d;}
   }
  }
 // A second motion only matters if it crosses near this cell; distant ones
 // (smooth zoom or rotation fields) would just defeat the fast path.
 if(secondDistance>1.5*FlowBlock)second=first;
 return float4(first,second);
}
float colorError(float3 a,float3 b) {
 float3 d=abs(a-b); return max(d.x,max(d.y,d.z));
}
bool inside(float2 p) { return all(p>=0)&&all(p<=ImageSize-1); }
float3 previousAt(float2 p) { return Previous.SampleLevel(LinearClamp,(p+0.5)*InvImageSize,0).rgb; }
float3 currentAt(float2 p) { return Current.SampleLevel(LinearClamp,(p+0.5)*InvImageSize,0).rgb; }
// Output colours: Catmull-Rom instead of bilinear. Motion rarely lands on
// whole pixels (half of an odd motion is x.5), and bilinear sampling there
// averages two texels, which would make every generated frame softer than
// the real frames around it (a sharpness flicker). Clamped to the four
// nearest texels, so edges get no overshoot halo.
float3 sharpAt(float2 p,bool current) {
 float2 q=clamp(p,float2(0,0),ImageSize-1);
 float2 base=floor(q), t=q-base;
 float2 w0=t*(-0.5+t*(1.0-0.5*t)), w1=1.0+t*t*(-2.5+1.5*t), w2=t*(0.5+t*(2.0-1.5*t)), w3=t*t*(-0.5+0.5*t);
 int2 maximum=int2(ImageSize)-1;
 float3 sum=float3(0,0,0), low=float3(1e9,1e9,1e9), high=float3(-1e9,-1e9,-1e9);
 float total=0;
 // The four corner taps (weights below 0.4% each) are skipped: 12 loads.
 [unroll] for(int y=0;y<4;++y){
  float wy=y==0?w0.y:(y==1?w1.y:(y==2?w2.y:w3.y));
  [unroll] for(int x=0;x<4;++x){
   if((x==0||x==3)&&(y==0||y==3))continue;
   float wx=x==0?w0.x:(x==1?w1.x:(x==2?w2.x:w3.x));
   int3 c=int3(clamp(int2(base)+int2(x-1,y-1),int2(0,0),maximum),0);
   float3 texel=current?Current.Load(c).rgb:Previous.Load(c).rgb;
   sum+=texel*(wx*wy);total+=wx*wy;
   if(x>=1&&x<=2&&y>=1&&y<=2){low=min(low,texel);high=max(high,texel);}
  }
 }
 return clamp(sum/total,low,high);
}
// Symmetric block match: previous at p-h against current at p+h. A small
// cross patch (center weighted) rejects coincidental single-pixel matches.
// gain is the pixel's estimated exposure change (see exposureGain); the
// same value is used for every candidate, so a wrong vector cannot pass a
// smooth gradient off as a brightness change.
// Also returns (y) the patch contrast: the largest difference between a
// cross sample and its centre in either frame, from the same loads.
float2 matchPatch(float2 p,float2 h,float3 gain) {
 float3 a=previousAt(p-h)*gain, b=currentAt(p+h);
 float cost=2*colorError(a,b), contrast=0;
 [unroll] for(int i=0;i<4;++i){
  float2 o=i==0?float2(1,0):(i==1?float2(-1,0):(i==2?float2(0,1):float2(0,-1)));
  float3 na=previousAt(p-h+o)*gain, nb=currentAt(p+h+o);
  cost+=colorError(na,nb); contrast=max(contrast,max(colorError(na,a),colorError(nb,b)));
 }
 return float2(cost/6,contrast);
}
float matchCost(float2 p,float2 h,float3 gain) { return matchPatch(p,h,gain).x; }
// Local exposure change between the frames (auto-exposure, flicker, moving
// shadows, light intensity) as a per-channel gain: exposure multiplies light,
// and a gain stays a gain after the display's power-law encoding. Estimated
// from nine colour ratios on a 7x7-pixel neighbourhood matched along the local
// motion, in log space. Robust: the ratio most consistent with the others
// (medoid) is found, then only ratios agreeing with it are averaged, so
// background samples still give an estimate beside an object. Fewer than four
// agreeing samples, or a gain beyond a plausible lighting change (scene cuts,
// flat differently coloured frames), gives no estimate (gain 1).
float3 exposureGain(float2 p,float2 motion) {
 float3 d[9];
 [unroll] for(int i=0;i<9;++i){
  float2 o=float2(i%3-1,i/3-1)*3;
  d[i]=log((currentAt(p+0.5*motion+o)+0.03)/(previousAt(p-0.5*motion+o)+0.03));
 }
 float3 medoid=d[4]; float bestSpread=1e9;
 [unroll] for(int j=0;j<9;++j){
  float spread=0;
  [unroll] for(int k=0;k<9;++k)spread+=colorError(d[j],d[k]);
  if(spread<bestSpread){bestSpread=spread;medoid=d[j];}
 }
 float3 sum=float3(0,0,0); float weight=0;
 [unroll] for(int m=0;m<9;++m){
  float w=1-smoothstep(0.025,0.06,colorError(d[m],medoid));
  sum+=d[m]*w; weight+=w;
 }
 float3 mean=sum/max(weight,0.001);
 float size=max(abs(mean.x),max(abs(mean.y),abs(mean.z)));
 float3 limited=clamp(mean,float3(-0.25,-0.25,-0.25),float3(0.25,0.25,0.25));
 return exp(limited*smoothstep(3.5,5.0,weight)*(1-smoothstep(0.25,0.4,size)));
}
bool changed(float3 gain) { return max(abs(gain.x-1),max(abs(gain.y-1),abs(gain.z-1)))>0.01; }
// Smallest difference between a color and the previous (or current) frame
// within one pixel of q; tolerates sub-pixel flow error on edges and texture.
float3 frameAt(float2 q,bool current) { return current?currentAt(q):previousAt(q); }
float nearestIn(float3 c,float2 q,bool current) {
 float e=colorError(c,frameAt(q,current));
 e=min(e,colorError(c,frameAt(q+float2(1,0),current)));
 e=min(e,colorError(c,frameAt(q-float2(1,0),current)));
 e=min(e,colorError(c,frameAt(q+float2(0,1),current)));
 return min(e,colorError(c,frameAt(q-float2(0,1),current)));
}
float nearestMatch(float3 c,float2 q) { return nearestIn(c,q,false); }
// Current colour c explained by the previous frame near q, with or without
// the estimated exposure change (lighting may not affect every object).
float explained(float3 c,float3 gain,float2 q) {
 float e=nearestMatch(c,q);
 [branch] if(changed(gain))e=min(e,nearestMatch(c/gain,q));
 return e;
}
float motionTolerance(float speed) { return 1.5+0.08*speed; }
// An occluder explains a one-sided pixel only if its own motion is reliable:
// forward/backward cycle consistent and photometrically matched. Both tests
// tolerate edge sampling because the occluder is found at its own boundary.
float occluder(float2 p,float2 motion,bool backward,float3 gain) {
 float2 end=p+motion;
 if(!inside(p)||!inside(end))return 0;
 // Unmixed cells: the occluder is usually sampled right at its own edge.
 float cycle=probe(end,float2(0,0)-motion,!backward).support;
 float tolerance=motionTolerance(length(motion));
 // With or without the exposure change: the occluder may be unlit by it.
 float3 own=frameAt(p,backward);
 float photo=nearestIn(own,end,!backward);
 [branch] if(changed(gain))
  photo=min(photo,nearestIn(backward?own/gain:own*gain,end,!backward));
 return (1-smoothstep(tolerance,2.5*tolerance,cycle))*(1-smoothstep(0.04,0.16,photo));
}
// Three best distinct candidate motions by a cheap one-sample match. Vectors
// within a pixel of a better entry are duplicates; the list stays sorted.
struct Ranking { float2 m0; float2 m1; float2 m2; float c0; float c1; float c2; };
Ranking rank(Ranking r,float2 m,float c) {
 bool near0=r.c0<1e8&&length(m-r.m0)<1, near1=r.c1<1e8&&length(m-r.m1)<1;
 bool near2=r.c2<1e8&&length(m-r.m2)<1;
 if((near0&&r.c0<=c)||(near1&&r.c1<=c)||(near2&&r.c2<=c))return r;
 if(near0){r.m0=m;r.c0=c;}
 else if(near1){r.m1=m;r.c1=c;}
 else if(near2||c<r.c2){r.m2=m;r.c2=c;}
 float2 tm; float tc;
 if(r.c1<r.c0){tm=r.m0;r.m0=r.m1;r.m1=tm;tc=r.c0;r.c0=r.c1;r.c1=tc;}
 if(r.c2<r.c1){tm=r.m1;r.m1=r.m2;r.m2=tm;tc=r.c1;r.c1=r.c2;r.c2=tc;}
 if(r.c1<r.c0){tm=r.m0;r.m0=r.m1;r.m1=tm;tc=r.c0;r.c0=r.c1;r.c1=tc;}
 return r;
}
// One-sided result: only one frame shows this midpoint pixel. The visible
// side must support the motion; the hidden side must be covered by a clearly
// different motion, or lie off-screen.
struct Side { float score; float3 color; float2 occluderAt; float2 occluder; bool edge; float2 motion; };
// Full validation of one candidate motion m. Flow probes are shared by the
// two-sided match and both one-sided (occlusion) interpretations.
struct Evaluation { float score; float confidence; float crossing; float flat; float3 color; Side fromCurrent; Side fromPrevious; };
// Two-sided midpoint colour of motion m, sharply resampled.
float3 midpointColor(float2 p,float2 m) { return 0.5*(sharpAt(p-0.5*m,false)+sharpAt(p+0.5*m,true)); }
// Contrast three pixels out in four directions, the smaller of both frames
// (detail must stand out in each).
float wideContrast(float2 q) {
 float3 c0=previousAt(q), c1=currentAt(q); float e0=0, e1=0;
 [unroll] for(int k=0;k<4;++k){
  float2 o=k==0?float2(3,0):(k==1?float2(-3,0):(k==2?float2(0,3):float2(0,-3)));
  e0=max(e0,colorError(c0,previousAt(q+o)));e1=max(e1,colorError(c1,currentAt(q+o)));
 }
 return min(e0,e1);
}
Evaluation evaluate(float2 p,float2 m,float2 reference,bool twoSided,float3 gain) {
 float2 h=0.5*m, pa=p-h, pb=p+h;
 float speed=length(m), tolerance=motionTolerance(speed);
 float limit=1-smoothstep(160.0,256.0,speed);
 bool insideA=inside(pa), insideB=inside(pb);
 // An occluder is recognized by its motion relative to m, which stays small
 // during fast pans; only flow error grows with the absolute speed.
 float different=2+0.03*speed;
 // Previous pixel should move by m; current pixel should move back by m.
 Probe forward=probe(pa,m,false), backward=probe(pb,float2(0,0)-m,true);
 float supportA=1-smoothstep(tolerance,2.5*tolerance,forward.support);
 float supportB=1-smoothstep(tolerance,2.5*tolerance,backward.support);
 float3 colorA=previousAt(pa), colorB=currentAt(pb);
 Evaluation r;
 r.score=4; r.confidence=0; r.crossing=0; r.flat=0; r.color=0.5*(colorA+colorB);
 if(twoSided&&insideA&&insideB){
  // Both directions must agree: a photometric match with contradictory
  // flow is treated as unreliable rather than guessed.
  float support=min(supportA,supportB)*limit;
  // Fix24 (Witcher 3 quest text over a moving sky): static content whose
  // flow reads zero in one direction only (the other direction's cells carry
  // the background moving behind it). Identity at this pixel and support
  // from one side suffice for the (near-)zero motion; otherwise a one-sided
  // fill along the background painted the sky over the letters.
  [branch] if(speed<1.0){
   float identity=colorError(colorA*gain,colorB);
   support=max(support,max(supportA,supportB)*(1-smoothstep(0.02,0.05,identity))*limit);
  }
  float2 patch=matchPatch(p,h,gain);
  float cost=patch.x;
  // Flat (untextured) endpoints that match tightly: clear sky, plain walls.
  // Optical flow has nothing to lock onto there, so its two directions often
  // disagree and the support above fails; yet the pixel is plainly visible
  // in both frames, and its midpoint colour barely depends on the motion.
  r.flat=(1-smoothstep(0.01,0.025,patch.y))*(1-smoothstep(0.03,0.06,cost))*limit;
  r.confidence=(1-smoothstep(0.04,0.16,cost))*support;
  // A second, clearly different motion supported by the flow at both ends
  // means an object crosses a still-visible background point, and occludes
  // it at the midpoint. Prefer it even with a looser match (sub-pixel flow
  // error on thin detail); otherwise poles and wires vanish.
  // Detail thinner than half a flow cell owns no block vector where it is
  // mostly background, so the flow may support its motion at one end only.
  // Then the other end must carry the background (reference) motion, which
  // rejects contradictory (corrupted) flow, and a much tighter photometric
  // match is required.
  float backgroundA=1-smoothstep(tolerance,2.5*tolerance,length(forward.flow-reference));
  float backgroundB=1-smoothstep(tolerance,2.5*tolerance,length(backward.flow+reference));
  float oneEnd=max(supportA*backgroundB,supportB*backgroundA)*limit*(1-smoothstep(0.02,0.06,cost))*0.9;
  float crossing=max(support*(1-smoothstep(0.06,0.25,cost)),oneEnd)*saturate((length(m-reference)-2)*0.25);
  // The crossing samples must belong to the moving object: background that
  // the reference motion already explains (e.g. beside an object's edge)
  // cannot claim the object's motion.
  [branch] if(crossing>0){
   float objectA=nearestIn(colorA*gain,pa+reference,true), objectB=nearestIn(colorB/gain,pb-reference,false);
   crossing*=smoothstep(0.04,0.12,min(objectA,objectB));
  }
  r.confidence=max(r.confidence,crossing);r.crossing=crossing;
  r.score=(1-r.confidence)+0.25*cost-0.6*crossing;
 }
 // Static overlay at one endpoint (Fix19: crosshair, HUD over a pan): the
 // endpoint lies on or within two pixels of overlay detail (OverlayNear),
 // and the endpoints do not match. The midpoint content is then visible
 // only in the other frame, and is taken from it without the occluder test
 // (the overlay does not move, so no flow describes it).
 // Fix18 fell back to the current frame there and pasted misplaced
 // background blocks half a motion away from the crosshair.
 float hudA=0, hudB=0;
 [branch] if(insideA&&insideB&&speed>=2){
  float mismatch=smoothstep(0.08,0.16,colorError(colorA*gain,colorB));
  [branch] if(mismatch>0){
   int2 last=int2(ImageSize)-1;
   float nearA=OverlayNear.Load(int3(clamp(int2(floor(pa+0.5)),int2(0,0),last),0));
   float nearB=OverlayNear.Load(int3(clamp(int2(floor(pb+0.5)),int2(0,0),last),0));
   // Both ends on overlay: nothing to recover from either frame.
   hudA=mismatch*nearA*(1-nearB);hudB=mismatch*nearB*(1-nearA);
  }
 }
 // Fix23 (Witcher 3: sword hilts and hair over a fast sky): a one-sided
 // sample must not be detail that stays in place in both frames. Such detail
 // did not move by m, so it cannot be at p at the midpoint; taking it
 // scattered copies of a nearly screen-fixed character into the sky.
 float staticA=0, staticB=0;
 [branch] if(speed>=3){
  float2 sa=insideA?matchPatch(pa,float2(0,0),gain):float2(1,0), sb=insideB?matchPatch(pb,float2(0,0),gain):float2(1,0);
  // Fix24: the interiors of thick HUD glyphs (Witcher 3 quest text) show no
  // contrast to the adjacent pixels; contrast three pixels out, in both
  // frames, counts too. Only for samples that stay in place and differ from
  // the other end (a one-sided fill would change the pixel): flat sky
  // matching itself needs no test.
  [branch] if(colorError(colorA*gain,colorB)>0.08){
   [branch] if(sa.x<0.1&&sa.y<0.12)sa.y=max(sa.y,wideContrast(pa));
   [branch] if(sb.x<0.1&&sb.y<0.12)sb.y=max(sb.y,wideContrast(pb));
  }
  staticA=(1-smoothstep(0.05,0.1,sa.x))*smoothstep(0.06,0.12,sa.y);
  staticB=(1-smoothstep(0.05,0.1,sb.x))*smoothstep(0.06,0.12,sb.y);
 }
 // Off-screen hidden side: its clamped border cells must still agree, which
 // holds for a real pan and rejects one-directional (corrupted) flow.
 r.fromCurrent.score=insideB?supportB*limit*(insideA?smoothstep(different,2*different,forward.deviation):supportA):0;
 r.fromCurrent.score=max(r.fromCurrent.score,hudA*supportB*limit)*(1-staticB);
 // One visible frame is brought to the midpoint exposure.
 r.fromCurrent.color=colorB/sqrt(gain); r.fromCurrent.occluderAt=pa; r.fromCurrent.occluder=forward.other; r.fromCurrent.edge=!insideA||hudA>0.5; r.fromCurrent.motion=m;
 r.fromPrevious.score=insideA?supportA*limit*(insideB?smoothstep(different,2*different,backward.deviation):supportB):0;
 r.fromPrevious.score=max(r.fromPrevious.score,hudB*supportA*limit)*(1-staticA);
 r.fromPrevious.color=colorA*sqrt(gain); r.fromPrevious.occluderAt=pb; r.fromPrevious.occluder=backward.other; r.fromPrevious.edge=!insideB||hudB>0.5; r.fromPrevious.motion=m;
 return r;
}
// Static overlay: textured detail fixed on screen although the flow here
// moves. HUD text and crosshairs drawn over a moving scene have this
// signature; world geometry does not (its flow follows it). Resolve keeps
// the real frame around clusters of these pixels, and synthesis takes the
// scene hidden behind them from the other frame.
float overlayTest(float2 p,float2 reference) {
 float4 original=float4(currentAt(p),1);
 float overlayFlag=0;
 float3 previous=previousAt(p);
 float identity=colorError(previous,original.rgb);
 [branch] if(identity<0.12){
  float3 left=currentAt(p-float2(1,0)), right=currentAt(p+float2(1,0));
  float3 up=currentAt(p-float2(0,1)), down=currentAt(p+float2(0,1));
  float3 pLeft=previousAt(p-float2(1,0)), pRight=previousAt(p+float2(1,0));
  float3 pUp=previousAt(p-float2(0,1)), pDown=previousAt(p+float2(0,1));
  float contrast=max(max(colorError(original.rgb,left),colorError(original.rgb,right)),
                     max(colorError(original.rgb,up),colorError(original.rgb,down)));
  // The detail must stand out in the previous frame as well. Plain sky or
  // wall right beside an object's new edge is also identical in both frames
  // and contrasts with the object in the current frame only; flagging it
  // made Resolve paste the next frame's edge ahead of the moving roofline.
  contrast=min(contrast,max(max(colorError(previous,pLeft),colorError(previous,pRight)),
                            max(colorError(previous,pUp),colorError(previous,pDown))));
  // Translucent overlays (Fix19: crosshairs, reticles, semi-transparent HUD)
  // are not identical in both frames: the moving scene shows through them.
  // Their edges are, though: the local differences to the four neighbours
  // stay the same at this pixel while the scene moves. Opaque detail passes
  // through identity; translucent detail through this structure test.
  float structure=max(max(colorError(original.rgb-left,previous-pLeft),colorError(original.rgb-right,previous-pRight)),
                      max(colorError(original.rgb-up,previous-pUp),colorError(original.rgb-down,previous-pDown)));
  bool fixedDetail=identity<0.02||(structure<min(0.1,0.3*contrast));
  // Every surrounding block must move in both directions: pixels of a
  // screen-fixed object (e.g. the character during a camera orbit) sit in
  // blocks with zero motion somewhere nearby and are never flagged.
  [branch] if(fixedDetail&&contrast>0.12){
   Probe still=probe(p,float2(0,0),true), stillForward=probe(p,float2(0,0),false);
   // The local motion must also fail to explain the pixel, otherwise it is
   // background that happens to match itself (flat or low-contrast areas).
   overlayFlag=(min(still.support,stillForward.support)>1.5&&
                nearestMatch(original.rgb,p-reference)>0.08)?2:0;
  }
 }
 return overlayFlag>0?1:0;
}
float OverlayMask(Vertex v) : SV_Target {
 float2 p=v.position.xy-0.5;
 return overlayTest(p,0.5*(flowAt(p,false)-flowAt(p,true)));
}
float OverlayGrow(Vertex v) : SV_Target {
 int2 c=int2(floor(v.position.xy)), m=int2(ImageSize)-1;
 float r=0;
 [unroll] for(int y=-2;y<=2;++y)
  [unroll] for(int x=-2;x<=2;++x)r=max(r,OverlayRaw.Load(int3(clamp(c+int2(x,y),int2(0,0),m),0)));
 return r;
}
// Candidate k: 0-3 forward cells around a, 4-7 backward cells around b,
// 8-15 the two projected motions of the four cells around p, 16 zero.
// One return path: D3DCompiler warned (X4000) about the early returns.
float2 candidateMotion(int k,int2 cellA,int2 cellB,int2 cellP,int2 maximum) {
 float2 m=float2(0,0);
 if(k<4)m=cellFlow(cellA+int2(k&1,k>>1),false);
 else if(k<8)m=float2(0,0)-cellFlow(cellB+int2(k&1,(k>>1)&1),true);
 else if(k<16){
  float4 pair=Projected.Load(int3(clamp(cellP+int2(k&1,(k>>1)&1),int2(0,0),maximum),0));
  m=(k&4)?float2(pair.z,pair.w):float2(pair.x,pair.y);
 }
 return m;
}
float4 Synthesize(Vertex v) : SV_Target {
 float2 p=v.position.xy-0.5, a=p, b=p;
 [unroll] for(int i=0;i<3;++i){a=p-0.5*flowAt(a,false);b=p-0.5*flowAt(b,true);}
 float4 original=Current.SampleLevel(LinearClamp,v.uv,0);
 float2 forwardMotion=flowAt(a,false), backwardMotion=float2(0,0)-flowAt(b,true);
 float2 reference=0.5*(forwardMotion+backwardMotion);
 int2 maximum=gridMaximum();
 int2 cellA=int2(floor(toGrid(a))), cellB=int2(floor(toGrid(b)));
 int2 cellP=int2(floor(toGrid(p)));
 // Candidates: unmixed block vectors around both midpoint correspondences,
 // motions projected through this cell, and zero. Per-pixel selection makes
 // object edges follow image content instead of the flow grid. A first pass
 // over the vectors alone (no colour samples) measures their spread.
 float spread=0;
 [loop] for(int s0=0;s0<16;++s0)spread=max(spread,length(candidateMotion(s0,cellA,cellB,cellP,maximum)-reference));
 // Static overlay: textured detail identical in both frames although the
 // flow here moves. HUD text drawn over a moving scene has this signature;
 // world geometry does not (its flow follows it). Resolve keeps the real
 // frame around clusters of these pixels, including antialiased glyph edges
 // and shadows that are blended with the moving background. The cheap
 // identity test runs first; the rest only for pixels that pass it.
 // Static overlay (HUD text, crosshair), from the OverlayMask pass.
 float overlayFlag=OverlayRaw.Load(int3(int2(floor(v.position.xy)),0))>0.5?2:0;
 // Fast path for uniformly moving regions, most of a typical frame: every
 // flow vector nearby agrees, the match is confident and the current pixel
 // itself moves with that motion (no thin or new detail to protect). It is
 // tried without the exposure estimate first; only if that fails is the
 // estimate computed (lighting changes) and the test repeated.
 float3 gain=float3(1,1,1);
 [branch] if(spread<1){
  Evaluation steady=evaluate(p,reference,reference,true,gain);
  if(steady.confidence>0.95&&nearestMatch(original.rgb,p-reference)<0.08)return float4(midpointColor(p,reference),1+overlayFlag);
 }
 // Flat fast path. In untextured areas (clear sky, plain walls, fog) the
 // flow is noisy, so the candidates spread far and Fix14 sent most of such
 // a frame through the full path, although no motion can change the
 // result there. Accepted when both midpoint ends along the reference are
 // flat and match tightly, the current pixel moves with it, and no nearby
 // motion carries clearly different, matching content (a pole or wire
 // crossing the sky must still take the full path).
 [branch] if(spread>=1){
  float2 h=0.5*reference;
  float2 patch=matchPatch(p,h,float3(1,1,1));
  [branch] if(patch.y<0.02&&patch.x<0.05&&inside(p-h)&&inside(p+h)&&nearestMatch(original.rgb,p-reference)<0.08){
   float3 flat=0.5*(previousAt(p-h)+currentAt(p+h));
   bool other=false;
   [loop] for(int f=0;f<16&&!other;++f){
    float2 m=candidateMotion(f,cellA,cellB,cellP,maximum);
    [branch] if(length(m-reference)>=1&&length(m)<256){
     float3 c0=previousAt(p-0.5*m), c1=currentAt(p+0.5*m);
     other=colorError(c0,c1)<0.08&&colorError(0.5*(c0+c1),flat)>0.06;
    }
   }
   if(!other)return float4(midpointColor(p,reference),1+overlayFlag);
  }
 }
 gain=exposureGain(p,reference);
 [branch] if(spread<1&&changed(gain)){
  Evaluation steady=evaluate(p,reference,reference,true,gain);
  if(steady.confidence>0.95&&explained(original.rgb,gain,p-reference)<0.08)return float4(midpointColor(p,reference),1+overlayFlag);
 }
 Ranking ranking;
 ranking.m0=ranking.m1=ranking.m2=float2(0,0); ranking.c0=ranking.c1=ranking.c2=1e9;
 // The best clearly deviating flow vector is always validated as well: a thin
 // crossing object can rank below background duplicates after flow noise.
 float2 deviating=float2(0,0); float deviatingCost=1e9;
 [loop] for(int k=0;k<17;++k){
  float2 m=candidateMotion(k,cellA,cellB,cellP,maximum);
  float2 h=0.5*m;
  if(length(m)<256&&inside(p-h)&&inside(p+h)){
   float c=colorError(previousAt(p-h)*gain,currentAt(p+h));
   ranking=rank(ranking,m,c);
   if(k<16&&length(m-reference)>3&&c<deviatingCost){deviating=m;deviatingCost=c;}
  }
 }
 // Near motion boundaries the interpolated reference mixes two motions, and
 // no consistent exposure change is found along it; retry along the best
 // matching candidate before the full evaluation.
 // The retried gain must explain the match along that motion clearly better
 // than no change (it is not accepted from border clamping or a mismatch).
 [branch] if(!changed(gain)&&ranking.c0<1e8&&length(ranking.m0-reference)>1){
  float3 retry=exposureGain(p,ranking.m0);
  float2 h0=0.5*ranking.m0;
  if(changed(retry)&&matchCost(p,h0,retry)<0.5*matchCost(p,h0,float3(1,1,1)))gain=retry;
 }
 float bestScore=4, bestConfidence=0, bestCrossing=0; float3 bestColor=original.rgb; float2 bestMotion=float2(0,0);
 float bestFlat=0; float2 flatMotion=float2(0,0);
 Side fromCurrent, fromPrevious;
 fromCurrent.score=fromPrevious.score=0; fromCurrent.color=fromPrevious.color=original.rgb;
 fromCurrent.occluderAt=fromPrevious.occluderAt=p; fromCurrent.occluder=fromPrevious.occluder=float2(0,0);
 fromCurrent.edge=fromPrevious.edge=false; fromCurrent.motion=fromPrevious.motion=float2(0,0);
 // Ranked motions plus the vectors reached from each side's own midpoint
 // correspondence (interpolated and nearest unmixed cell), which are the
 // usual visible-background motions in occlusion bands.
 [loop] for(int n=0;n<8;++n){
  float2 m=forwardMotion; bool ranked=n<4;
  if(n==0)m=ranking.m0; else if(n==1)m=ranking.m1; else if(n==2)m=ranking.m2; else if(n==3)m=deviating;
  else if(n==5)m=backwardMotion;
  else if(n==6)m=cellFlow(int2(floor(toGrid(a)+0.5)),false);
  else if(n==7)m=float2(0,0)-cellFlow(int2(floor(toGrid(b)+0.5)),true);
  float rankedCost=n==0?ranking.c0:(n==1?ranking.c1:(n==2?ranking.c2:(n==3?deviatingCost:0)));
  if(rankedCost<1e8){
   Evaluation e=evaluate(p,m,reference,ranked,gain);
   if(ranked&&e.score<bestScore){bestScore=e.score;bestConfidence=e.confidence;bestCrossing=e.crossing;bestColor=e.color;bestMotion=m;}
   if(e.flat>bestFlat){bestFlat=e.flat;flatMotion=m;}
   // Screen borders are valid one-sided evidence; otherwise require a real,
   // self-consistent occluder, which rejects fabricated or scene-cut flow.
   // Several motions often tie before this test (a boundary pixel supports
   // both the object and the background), so every interpretation that
   // could still win is validated, not only the first of equal scores.
   [branch] if(e.fromCurrent.score>fromCurrent.score){
    if(!e.fromCurrent.edge)e.fromCurrent.score*=occluder(e.fromCurrent.occluderAt,e.fromCurrent.occluder,false,gain);
    if(e.fromCurrent.score>fromCurrent.score)fromCurrent=e.fromCurrent;
   }
   [branch] if(e.fromPrevious.score>fromPrevious.score){
    if(!e.fromPrevious.edge)e.fromPrevious.score*=occluder(e.fromPrevious.occluderAt,e.fromPrevious.occluder,true,gain);
    if(e.fromPrevious.score>fromPrevious.score)fromPrevious=e.fromPrevious;
   }
  }
 }
 float oneSided=max(fromCurrent.score,fromPrevious.score);
 // Selection used the cheap bilinear colours; the chosen interpretations
 // are resampled sharply (only where they contribute).
 bool useCurrent=fromCurrent.score>=fromPrevious.score;
 // A flat, tightly matching pair means both frames show this pixel, so it
 // is not one-sided. Fix14 accepted one-sided samples there and filled the
 // rest from the unwarped current frame: over clear sky both put slivers of
 // the next frame's roof or wall edge ahead of the real, moving edge.
 float weightB=bestConfidence, weightO=(1-bestConfidence)*oneSided*(1-bestFlat);
 [branch] if(weightB>0.001)bestColor=midpointColor(p,bestMotion);
 float3 oneColor=useCurrent?fromCurrent.color:fromPrevious.color;
 [branch] if(weightO>0.001)oneColor=useCurrent?sharpAt(p+0.5*fromCurrent.motion,true)/sqrt(gain):sharpAt(p-0.5*fromPrevious.motion,false)*sqrt(gain);
 // The rest is filled from that flat pair, where the current pixel clearly
 // differs from it (misplaced content); in smooth shading the unwarped
 // fallback is already close.
 float weightF=0; float3 flatColor=original.rgb;
 [branch] if(bestFlat>0.001){
  flatColor=0.5*(previousAt(p-0.5*flatMotion)*sqrt(gain)+currentAt(p+0.5*flatMotion)/sqrt(gain));
  weightF=(1-weightB-weightO)*bestFlat*smoothstep(0.08,0.16,colorError(original.rgb,flatColor));
 }
 // Fix21: what is still unexplained falls back to the midpoint along the
 // local motion instead of the unwarped current frame (misplaced by half the
 // motion), where the scene clearly moves and both frames roughly agree.
 float weightR=0; float3 refColor=original.rgb;
 // Not at static overlays (crosshair, HUD): Resolve keeps those.
 float nearOverlay=OverlayNear.Load(int3(int2(floor(v.position.xy)),0));
 [branch] if(weightB+weightO+weightF<0.999&&length(reference)>=1&&nearOverlay<0.5){
  // Fix24: the best matching of the local motion and the ranked candidates
  // (patch match only: where the flow itself is wrong, e.g. dragged to zero
  // around static HUD panels, no candidate has flow support at its ends).
  // Only needed where the local motion itself matches poorly.
  float2 hr=0.5*reference; float refCost=inside(p-hr)&&inside(p+hr)?matchCost(p,hr,gain):9;
  [branch] if(refCost>0.1){
   [unroll] for(int r=0;r<3;++r){
    float2 m=r==0?ranking.m0:(r==1?ranking.m1:ranking.m2);
    float rc=r==0?ranking.c0:(r==1?ranking.c1:ranking.c2);
    [branch] if(rc<0.1&&length(m)>=1&&inside(p-0.5*m)&&inside(p+0.5*m)){
     float c=matchCost(p,0.5*m,gain);
     if(c<refCost){refCost=c;hr=0.5*m;}
    }
   }
  }
  [branch] if(refCost<1){
   float3 ra=previousAt(p-hr)*sqrt(gain), rb=currentAt(p+hr)/sqrt(gain);
   refColor=0.5*(ra+rb);
   weightR=(1-weightB-weightO-weightF)*smoothstep(1.0,3.0,2*length(hr))*(1-smoothstep(0.1,0.25,refCost));
  }
 }
 float valid=weightB+weightO+weightF+weightR;
 float3 color=valid>0.001?(weightB*bestColor+weightO*oneColor+weightF*flatColor+weightR*refColor)/valid:original.rgb;
 // Current content without any correspondence (a new object, or detail too
 // thin for the flow grid) stays where the real frame shows it instead of
 // breaking into fragments. Each unmixed block vector is tested separately;
 // revealed background is excluded because its previous-frame location is
 // covered by a different, occluding motion.
 float here=explained(original.rgb,gain,p);
 float keep=smoothstep(0.08,0.2,here);
 // A candidate motion that explains the current pixel from the previous frame
 // (e.g. a thin object found through the projected motions) also counts.
 keep*=smoothstep(0.08,0.2,explained(original.rgb,gain,p-ranking.m0));
 if(deviatingCost<1e8)keep*=smoothstep(0.08,0.2,explained(original.rgb,gain,p-deviating));
 [unroll] for(int j=0;j<4;++j){
  float2 u=cellFlow(cellP+int2(j&1,j>>1),true), q=p+u;
  float uTolerance=motionTolerance(length(u));
  float revealed=inside(q)?smoothstep(uTolerance,2.5*uTolerance,
   length(cellFlow(int2(floor(toGrid(q)+0.5)),false)+u)):1;
  // Scene that was behind a static overlay (crosshair, HUD) in the previous
  // frame is not new either (Fix19): it moves with the scene.
  if(inside(q))revealed=max(revealed,OverlayNear.Load(int3(int2(floor(q+0.5)),0)));
  keep*=smoothstep(0.08,0.2,explained(original.rgb,gain,q))*(1-revealed);
 }
 // Thin static detail present at exactly this pixel in both frames but
 // replaced by a background match: no flow describes it, so keep it too.
 // (A one-pixel tolerance would also accept thin objects moving about a
 // pixel across themselves, which do move.)
 float3 left=currentAt(p-float2(1,0)), right=currentAt(p+float2(1,0));
 float3 up=currentAt(p-float2(0,1)), down=currentAt(p+float2(0,1));
 float thin=max(smoothstep(0.08,0.16,min(colorError(original.rgb,left),colorError(original.rgb,right))),
                smoothstep(0.08,0.16,min(colorError(original.rgb,up),colorError(original.rgb,down))));
 float stay=min(colorError(original.rgb,previousAt(p)),colorError(original.rgb/gain,previousAt(p)));
 keep=max(keep,(1-smoothstep(0.03,0.08,stay))*smoothstep(0.1,0.2,colorError(color,original.rgb))*thin);
 // Fix23: content identical at this pixel in both frames (patch match with
 // no motion) does not move with the pan. When the chosen colour is just
 // the background along the pan (sky at both ends), that content is a
 // nearly screen-fixed foreground (a character's sword hilts, hair, armour
 // over a fast sky) and is there at the midpoint too; before, only one- or
 // two-pixel-thin detail was kept. A crossing object (clearly different
 // motion) may still pass over it.
 [branch] if(length(bestMotion)>=3&&weightB>0.5&&colorError(color,original.rgb)>0.1){
  float still=0;
  float here0=colorError(previousAt(p),original.rgb);
  here0=min(here0,min(min(colorError(previousAt(p+float2(1,0)),original.rgb),colorError(previousAt(p-float2(1,0)),original.rgb)),
                      min(colorError(previousAt(p+float2(0,1)),original.rgb),colorError(previousAt(p-float2(0,1)),original.rgb))));
  float background=1-smoothstep(0.02,0.05,here0);
  // The static content must have a static edge nearby (its own outline):
  // flat interiors of moving surfaces are identical in both frames too.
  float edge=0;
  [unroll] for(int e=0;e<8;++e){
   float2 o=3*float2(e<3?e-1:(e<5?(e==3?-1:1):e-6),e<3?-1:(e<5?0:1));
   float3 ec=currentAt(p+o);
   float moved=colorError(previousAt(p+o),ec);
   moved=min(moved,min(min(colorError(previousAt(p+o+float2(1,0)),ec),colorError(previousAt(p+o-float2(1,0)),ec)),
                       min(colorError(previousAt(p+o+float2(0,1)),ec),colorError(previousAt(p+o-float2(0,1)),ec))));
   edge=max(edge,smoothstep(0.1,0.2,colorError(ec,original.rgb))*(1-smoothstep(0.03,0.08,moved)));
  }
  background*=edge;
  keep=max(keep,(1-smoothstep(0.03,0.06,still))*background*(1-bestCrossing)*smoothstep(0.1,0.2,colorError(color,original.rgb)));
 }
 // Fix24: cores of static HUD glyphs (Witcher 3 quest text): identical in both
 // frames, standing out three pixels away in each (thick strokes have no
 // contrast to adjacent pixels), next to clearly moving, cycle-consistent flow
 // that does not explain them. Kept exactly (only the glyph itself).
 [branch] if(keep<0.99&&colorError(color,original.rgb)>0.1&&colorError(previousAt(p),original.rgb)<0.04&&wideContrast(p)>0.2){
  float glyph=0;
  [unroll] for(int k=0;k<8;++k){
   float2 d=k<4?float2((k&1)!=0?1.0:-1.0,(k&2)!=0?1.0:-1.0)*0.7071:float2(k==4?1.0:(k==5?-1.0:0.0),k==6?1.0:(k==7?-1.0:0.0));
   float2 q=p+d*(3*FlowBlock);
   float2 f=flowAt(q,false), bk=flowAt(q,true);
   float speed=length(f);
   if(inside(q)&&speed>2&&length(f+bk)<motionTolerance(speed)&&explained(original.rgb,gain,p-f)>0.1)glyph=1;
  }
  keep=max(keep,glyph);
 }
 color=lerp(color,original.rgb,keep);
 // A confident crossing object: its midpoint pixel may look screen-stationary
 // (the object has left it in both real frames), which Resolve must not
 // mistake for UI. Flagged by +4 in alpha.
 float crossingFlag=(bestCrossing>0.5&&weightB>0.5*valid&&keep<0.5)?4:0;
 return float4(color,max(valid,keep)+overlayFlag+crossingFlag);
}
float stationaryError(float2 uv) {
 return colorError(Previous.SampleLevel(LinearClamp,uv,0).rgb,
                   Current.SampleLevel(LinearClamp,uv,0).rgb);
}
// Reprojection alpha: confidence (0..1) + 2 overlay flag + 4 crossing flag.
float confidenceOf(float w) { w=w>=3.5?w-4:w; return w>=1.5?w-2:w; }
bool overlayOf(float w) { w=w>=3.5?w-4:w; return w>=1.5; }
float4 Resolve(Vertex v) : SV_Target {
 float4 original=Current.SampleLevel(LinearClamp,v.uv,0);
 float4 candidate=Reprojection.Load(int3(int2(floor(v.position.xy)),0));
 float centerValid=confidenceOf(candidate.w);
 float crossing=candidate.w>=3.5?1:0;
 // Neighborhood support removes isolated confident samples and feathers the
 // fallback by about one pixel. Unlike a wide minimum filter it does not cut
 // current-frame blocks, misplaced by half the motion, into the midpoint.
 // The 5x5 overlay count finds HUD text over moving background.
 float support=0, overlays=0;
 [unroll] for(int y=-2;y<=2;++y)
  [unroll] for(int x=-2;x<=2;++x){
   float w=Reprojection.Load(int3(clamp(int2(floor(v.position.xy))+int2(x,y),int2(0,0),int2(ImageSize)-1),0)).w;
   overlays+=overlayOf(w)?1:0;
   if(abs(x)<=1&&abs(y)<=1)support+=confidenceOf(w);
  }
 float confidence=smoothstep(0.2,0.9,min(centerValid,support*(1.25/9)));
 // A confident crossing object is not HUD text (static glyphs have no
 // clearly different, flow-supported motion), so stray flags nearby are
 // ignored for it.
 confidence*=1-smoothstep(0.25,1.5,overlays)*(1-crossing);
 // Screen-stationary detail is often UI. Require support from at least one
 // neighboring pixel to avoid pinning isolated color coincidences in motion.
 float nearby=min(min(stationaryError(v.uv+float2(1,0)*InvImageSize),
                      stationaryError(v.uv-float2(1,0)*InvImageSize)),
                  min(stationaryError(v.uv+float2(0,1)*InvImageSize),
                      stationaryError(v.uv-float2(0,1)*InvImageSize)));
 float stationary=1-smoothstep(0.004,0.016,max(stationaryError(v.uv),nearby));
 // Fix21: flat areas look stationary too (clear sky is equal in both real
 // frames), yet a thin object may cross them in between, like a chimney
 // passing over sky. UI keeps detail of its own, so the stationary override
 // needs local contrast, or a candidate close to the current frame anyway.
 float3 o1=Current.SampleLevel(LinearClamp,v.uv+float2(1,0)*InvImageSize,0).rgb, o2=Current.SampleLevel(LinearClamp,v.uv-float2(1,0)*InvImageSize,0).rgb;
 float3 o3=Current.SampleLevel(LinearClamp,v.uv+float2(0,1)*InvImageSize,0).rgb, o4=Current.SampleLevel(LinearClamp,v.uv-float2(0,1)*InvImageSize,0).rgb;
 float detail=smoothstep(0.04,0.1,max(max(colorError(original.rgb,o1),colorError(original.rgb,o2)),max(colorError(original.rgb,o3),colorError(original.rgb,o4))));
 detail=max(detail,1-smoothstep(0.05,0.15,colorError(candidate.rgb,original.rgb)));
 confidence*=1-stationary*detail*(1-crossing);
 // Fix24: where nothing explains the pixel, soft low-contrast content (clouds,
 // fog, smooth shading) falls back to a cross-fade of both frames instead of
 // the unwarped current frame, which is misplaced by half the motion and
 // leaves a patchwork of two cloud states. Textured content keeps the
 // current frame (a cross-fade would double its edges). Only evaluated
 // where the candidate is not fully trusted.
 float3 fallback=original.rgb;
 [branch] if(confidence<0.999){
  float3 previousHere=Previous.SampleLevel(LinearClamp,v.uv,0).rgb;
  float local=0;
  [unroll] for(int k=0;k<4;++k){
   float2 o=(k==0?float2(2,0):(k==1?float2(-2,0):(k==2?float2(0,2):float2(0,-2))))*InvImageSize;
   local=max(local,max(colorError(Current.SampleLevel(LinearClamp,v.uv+o,0).rgb,original.rgb),
                       colorError(Previous.SampleLevel(LinearClamp,v.uv+o,0).rgb,previousHere)));
  }
  float soft=1-smoothstep(0.06,0.15,local);
  // Only where both frames are close at this pixel: a strong difference
  // means an edge or object moved here (a cross-fade would leave its
  // translucent ghost) or the scene changed (cut). Never next to static
  // overlays (HUD text keeps the current frame) or on stationary pixels.
  float close=1-smoothstep(0.25,0.55,colorError(previousHere,original.rgb));
  fallback=lerp(original.rgb,0.5*(previousHere+original.rgb),soft*close*(1-stationary)*(1-smoothstep(0.25,1.5,overlays)));
 }
 return float4(lerp(fallback,candidate.rgb,confidence),original.w);
}
// DX11 multisampled backbuffers (Fix15): frames are written back by drawing,
// every sample receiving the pixel. The textures hold the backbuffer's bytes
// read as UNORM; for an sRGB backbuffer the render target encodes again, so
// BlitSrgb decodes first and the bytes come back unchanged.
float4 Blit(Vertex v) : SV_Target { return Previous.Load(int3(int2(floor(v.position.xy)),0)); }
float srgbToLinear(float c) { return c<=0.04045?c/12.92:pow((c+0.055)/1.055,2.4); }
float4 BlitSrgb(Vertex v) : SV_Target {
 float4 c=Previous.Load(int3(int2(floor(v.position.xy)),0));
 return float4(srgbToLinear(c.x),srgbToLinear(c.y),srgbToLinear(c.z),c.w);
}
