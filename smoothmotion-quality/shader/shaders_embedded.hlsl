// SmoothMotion fix28-qua2 synthesis. Commented source: smoothmotion-quality/shader/shaders.hlsl (dlssg_for_sm86).
Texture2D<float4> Previous : register(t0);
Texture2D<float4> Current : register(t1);
Texture2D<int2> Forward : register(t2);
Texture2D<int2> Backward : register(t3);
Texture2D<float4> Reprojection : register(t4);
Texture2D<float4> Projected : register(t5);
Texture2D<float> OverlayRaw : register(t6);
Texture2D<float2> OverlayNear : register(t7);
Texture2D<float4> Dominant : register(t8);
Texture2D<float4> Choice : register(t9);
SamplerState LinearClamp : register(s0);
cbuffer Settings : register(b0) { float2 ImageSize; float2 InvImageSize; float FlowBlock; float FlowGain; float2 SettingsPad; };
struct Vertex { float4 position : SV_Position; float2 uv : TEXCOORD0; };
Vertex Fullscreen(uint id : SV_VertexID) {
Vertex v; v.uv=float2((id<<1)&2,id&2);
v.position=float4(v.uv*float2(2,-2)+float2(-1,1),0,1); return v;
}
float4 Capture(Vertex v) : SV_Target { return Previous.SampleLevel(LinearClamp,v.uv,0); }
int2 gridMaximum() { return int2(ceil(ImageSize/FlowBlock))-1; }
float2 toGrid(float2 p) { return (p-(FlowBlock-1)*0.5)/FlowBlock; }
float2 cellCenter(int2 c) { return float2(c)*FlowBlock+(FlowBlock-1)*0.5; }
float2 cellFlow(int2 c,bool backward) {
c=clamp(c,int2(0,0),gridMaximum());
if(backward)return Backward.Load(int3(c,0))*FlowGain;
return Forward.Load(int3(c,0))*FlowGain;
}
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
if(secondDistance>1.5*FlowBlock)second=first;
return float4(first,second);
}
static const float invalidMotion=16384;
float4 DominantMotion(Vertex v) : SV_Target {
int2 base=int2(floor(v.position.xy))*2, maximum=gridMaximum();
int outer=FlowBlock<6?8:4, innerStride=FlowBlock<6?4:2;
float2 s[68]; float distance2[34];
[unroll] for(int i=0;i<34;++i){
uint u=uint(i), v=uint(i-25);
int2 o=i<25?(int2(u%5,u/5)-2)*outer:(int2(v%3,v/3)-1)*innerStride;
int2 c=clamp(base+o,int2(0,0),maximum);
s[i]=cellFlow(c,false); s[34+i]=float2(0,0)-cellFlow(c,true);
float2 d=float2(c-base)*FlowBlock; distance2[i]=dot(d,d);
}
float count[68];
[loop] for(int j=0;j<68;++j){
float tolerance=2+0.05*length(s[j]), inForward=0, inBackward=0;
[loop] for(int k=0;k<34;++k){inForward+=length(s[j]-s[k])<tolerance?1:0;inBackward+=length(s[j]-s[34+k])<tolerance?1:0;}
count[j]=min(inForward,inBackward)>=3?inForward+inBackward:0;
}
float2 first=s[12]; float firstCount=0;
[loop] for(int a=0;a<68;++a)if(count[a]>firstCount){firstCount=count[a];first=s[a];}
float2 second=first; float secondCount=0; float separation=4+0.1*length(first);
[loop] for(int b=0;b<68;++b)if(count[b]>secondCount&&length(s[b]-first)>separation){secondCount=count[b];second=s[b];}
if(firstCount<3)return float4(invalidMotion,invalidMotion,invalidMotion,invalidMotion);
if(secondCount<3)second=first;
float3 sumFirst=float3(0,0,0), sumSecond=float3(0,0,0);
float looseFirst=2+0.15*length(first), looseSecond=2+0.15*length(second);
[loop] for(int m=0;m<68;++m){
float w=1/(1+distance2[m<34?m:m-34]*(1.0/576));
if(length(s[m]-first)<looseFirst)sumFirst+=float3(s[m]*w,w);
else if(length(s[m]-second)<looseSecond)sumSecond+=float3(s[m]*w,w);
}
if(sumFirst.z>0)first=float2(sumFirst.x,sumFirst.y)/sumFirst.z;
if(sumSecond.z>0&&secondCount>=3)second=float2(sumSecond.x,sumSecond.y)/sumSecond.z;
return float4(first,second);
}
float4 dominantAt(float2 p) {
int2 last=int2(ceil(ImageSize/(2*FlowBlock)))-1;
float2 u=(p-(FlowBlock-0.5))/(2*FlowBlock);
int2 i=int2(floor(u)); float2 t=frac(u);
float4 a=Dominant.Load(int3(clamp(i,int2(0,0),last),0)), b=Dominant.Load(int3(clamp(i+int2(1,0),int2(0,0),last),0));
float4 c=Dominant.Load(int3(clamp(i+int2(0,1),int2(0,0),last),0)), d=Dominant.Load(int3(clamp(i+int2(1,1),int2(0,0),last),0));
float4 nearest=t.y<0.5?(t.x<0.5?a:b):(t.x<0.5?c:d);
float spread=max(max(length(a.xy-b.xy),length(a.xy-c.xy)),max(length(a.xy-d.xy),max(length(b.xy-c.xy),max(length(b.xy-d.xy),length(c.xy-d.xy)))));
if(nearest.x>=0.5*invalidMotion||spread>2+0.05*length(nearest.xy))return nearest;
float4 mixed=lerp(lerp(a,b,t.x),lerp(c,d,t.x),t.y);
return float4(mixed.x,mixed.y,nearest.z,nearest.w);
}
float colorError(float3 a,float3 b) {
float3 d=abs(a-b); return max(d.x,max(d.y,d.z));
}
bool inside(float2 p) { return all(p>=0)&&all(p<=ImageSize-1); }
float3 previousAt(float2 p) { return Previous.SampleLevel(LinearClamp,(p+0.5)*InvImageSize,0).rgb; }
float3 currentAt(float2 p) { return Current.SampleLevel(LinearClamp,(p+0.5)*InvImageSize,0).rgb; }
float3 sharpAt(float2 p,bool current) {
float2 q=clamp(p,float2(0,0),ImageSize-1);
float2 base=floor(q), t=q-base;
float2 w0=t*(-0.5+t*(1.0-0.5*t)), w1=1.0+t*t*(-2.5+1.5*t), w2=t*(0.5+t*(2.0-1.5*t)), w3=t*t*(-0.5+0.5*t);
int2 maximum=int2(ImageSize)-1;
float3 sum=float3(0,0,0), low=float3(1e9,1e9,1e9), high=float3(-1e9,-1e9,-1e9);
float total=0;
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
float2 matchPatchWith(float2 p,float2 h,float3 gain,float3 centerA,float3 centerB) {
float3 a=centerA*gain, b=centerB;
float cost=2*colorError(a,b), contrast=0;
[unroll] for(int i=0;i<4;++i){
float2 o=i==0?float2(1,0):(i==1?float2(-1,0):(i==2?float2(0,1):float2(0,-1)));
float3 na=previousAt(p-h+o)*gain, nb=currentAt(p+h+o);
cost+=colorError(na,nb); contrast=max(contrast,max(colorError(na,a),colorError(nb,b)));
}
return float2(cost/6,contrast);
}
float3 matchPatchAxes(float2 p,float2 h,float3 gain,float3 centerA,float3 centerB) {
float3 a=centerA*gain, b=centerB;
float c0=colorError(a,b), contrast=0; float e[4];
[unroll] for(int i=0;i<4;++i){
float2 o=i==0?float2(1,0):(i==1?float2(-1,0):(i==2?float2(0,1):float2(0,-1)));
float3 na=previousAt(p-h+o)*gain, nb=currentAt(p+h+o);
e[i]=colorError(na,nb); contrast=max(contrast,max(colorError(na,a),colorError(nb,b)));
}
return float3((2*c0+e[0]+e[1]+e[2]+e[3])/6,contrast,(2*c0+2*min(e[0]+e[1],e[2]+e[3]))/6);
}
float2 matchPatch(float2 p,float2 h,float3 gain) { return matchPatchWith(p,h,gain,previousAt(p-h),currentAt(p+h)); }
float matchCost(float2 p,float2 h,float3 gain) { return matchPatch(p,h,gain).x; }
bool movesBesideOverlay(float2 p,float2 m,float3 current,float3 previous) {
if(length(m)<2||!inside(p-m)||!inside(p+m))return false;
return colorError(current,previousAt(p-m))<0.03&&colorError(previous,currentAt(p+m))<0.03;
}
bool movesHere(float2 p,float2 m,float3 gain) {
if(!inside(p-m)||!inside(p+m))return false;
float2 still=matchPatch(p,float2(0,0),gain);
if(still.x<0.02&&still.y>0.08)return false;
return matchPatch(p-0.5*m,0.5*m,gain).x<0.02&&matchPatch(p+0.5*m,0.5*m,gain).x<0.02;
}
float3 exposureGain(float2 p,float2 motion) {
float3 d[9];
[unroll] for(int i=0;i<9;++i){
float2 o=float2(i%3-1,i/3-1)*3;
d[i]=log((currentAt(p+0.5*motion+o)+0.03)/(previousAt(p-0.5*motion+o)+0.03));
}
float3 medoid=d[4]; float bestSpread=1e9;
[loop] for(int j=0;j<9;++j){
float spread=0;
[loop] for(int k=0;k<9;++k)spread+=colorError(d[j],d[k]);
if(spread<bestSpread){bestSpread=spread;medoid=d[j];}
}
float3 sum=float3(0,0,0); float weight=0;
[loop] for(int m=0;m<9;++m){
float w=1-smoothstep(0.025,0.06,colorError(d[m],medoid));
sum+=d[m]*w; weight+=w;
}
float3 mean=sum/max(weight,0.001);
float size=max(abs(mean.x),max(abs(mean.y),abs(mean.z)));
float range=0.25;
[branch] if(size>0.25&&weight>=5){
float agree=0;
[unroll] for(int f=0;f<4;++f){
float2 o=f==0?float2(12,0):(f==1?float2(-12,0):(f==2?float2(0,12):float2(0,-12)));
float3 far=log((currentAt(p+0.5*motion+o)+0.03)/(previousAt(p-0.5*motion+o)+0.03));
agree+=colorError(far,mean)<0.06?1:0;
}
if(agree>=3)range=0.7;
}
float3 limited=clamp(mean,-float3(range,range,range),float3(range,range,range));
return exp(limited*smoothstep(3.5,5.0,weight)*(1-smoothstep(range,range+0.15+0.05*(range>0.3?1:0),size)));
}
bool changed(float3 gain) { return max(abs(gain.x-1),max(abs(gain.y-1),abs(gain.z-1)))>0.01; }
float3 frameAt(float2 q,bool current) { return current?currentAt(q):previousAt(q); }
float nearestIn(float3 c,float2 q,bool current) {
float e=colorError(c,frameAt(q,current));
e=min(e,colorError(c,frameAt(q+float2(1,0),current)));
e=min(e,colorError(c,frameAt(q-float2(1,0),current)));
e=min(e,colorError(c,frameAt(q+float2(0,1),current)));
return min(e,colorError(c,frameAt(q-float2(0,1),current)));
}
float nearestMatch(float3 c,float2 q) { return nearestIn(c,q,false); }
float explained(float3 c,float3 gain,float2 q) {
float e=nearestMatch(c,q);
[branch] if(changed(gain))e=min(e,nearestMatch(c/gain,q));
return e;
}
float motionTolerance(float speed) { return 1.5+0.08*speed; }
float3 refineMatch(float3 own[16],float3 mean,float2 center,float step,float2 m,bool backward) {
if(!inside(center+m))return float3(9,0,9);
float3 other[16]; float3 sum=float3(0,0,0);
[unroll] for(int i=0;i<16;++i){
float2 q=center+(float2(i&3,i>>2)-1.5)*step+m;
other[i]=backward?previousAt(q):currentAt(q); sum+=other[i];
}
float3 gain=clamp((mean+0.02)/(sum*0.0625+0.02),float3(0.7,0.7,0.7),float3(1.4,1.4,1.4));
if(max(abs(gain.x-1),max(abs(gain.y-1),abs(gain.z-1)))<0.06||mean.x+mean.y+mean.z<0.6)gain=float3(1,1,1);
float cost=0, matched=0, compensated=0;
[unroll] for(int j=0;j<16;++j){
float3 d=abs(own[j]-other[j]); float e=d.x+d.y+d.z;
cost+=min(e,0.6); matched+=e<0.15?1:0;
float3 dg=abs(own[j]-other[j]*gain); compensated+=min(dg.x+dg.y+dg.z,0.6);
}
return float3(cost/48,matched,compensated/48);
}
float refineCost(float3 own[16],float2 center,float step,float2 m,bool backward) {
if(!inside(center+m))return 9;
float sum=0;
[unroll] for(int i=0;i<16;++i){
float2 q=center+(float2(i&3,i>>2)-1.5)*step+m;
float3 d=abs(own[i]-(backward?previousAt(q):currentAt(q)));
sum+=min(d.x+d.y+d.z,0.6);
}
return sum/48;
}
int2 refineCell(int2 cell,bool backward) {
float2 center=cellCenter(cell);
float step=0.25*FlowBlock;
float3 own[16]; float3 mean=float3(0,0,0);
[unroll] for(int i=0;i<16;++i){
float2 q=center+(float2(i&3,i>>2)-1.5)*step;
own[i]=backward?currentAt(q):previousAt(q);
mean+=own[i];
}
mean=mean*0.0625;
float2 raw=cellFlow(cell,backward);
float3 rawMatch=refineMatch(own,mean,center,step,raw,backward);
float rawCost=rawMatch.x;
float2 best=raw; float bestCost=rawCost;
float2 adopted=raw; bool found=false, consistent=false;
[branch] if(rawCost>0.02&&rawCost<9&&rawMatch.z>0.02){
float2 reverse=cellFlow(int2(floor(toGrid(center+raw)+0.5)),!backward);
consistent=length(raw+reverse)<2*motionTolerance(length(raw))+2;
{
float2 last=raw;
[loop] for(int k=0;k<32;++k){
if(k==16&&bestCost<0.03&&bestCost<0.5*rawCost)break;
int ring=k<8?1:(k<16?2:(k<24?4:6)); int d=k&7;
int2 o=int2(d<3?d-1:(d==3?-1:(d==4?1:d-6)),d<3?-1:(d<5?0:1))*ring;
int2 source=clamp(cell+o,int2(0,0),gridMaximum());
float2 m=cellFlow(source,backward);
[branch] if(length(m-raw)>=1&&length(m)<256){
float2 c0=cellCenter(source); float3 sum=float3(0,0,0); float own2=9;
bool adoptable=!found&&length(m)>=0.5&&inside(c0+m)&&inside(center+m);
[branch] if(adoptable){
own2=0;
[unroll] for(int i=0;i<4;++i){
float2 q=c0+(float2(i&1,i>>1)-0.5)*(0.5*FlowBlock);
float3 a=backward?currentAt(q):previousAt(q), b=backward?previousAt(q+m):currentAt(q+m);
float3 e=abs(a-b); sum+=a; own2+=min(e.x+e.y+e.z,0.6);
}
}else{
[unroll] for(int i=0;i<4;++i){
float2 q=c0+(float2(i&1,i>>1)-0.5)*(0.5*FlowBlock);
sum+=backward?currentAt(q):previousAt(q);
}
}
[branch] if(colorError(0.25*sum,mean)<0.12&&length(m-last)>=0.25){
last=m;
float c=refineCost(own,center,step,m,backward);
if(c<bestCost){bestCost=c;best=m;}
}
[branch] if(adoptable&&own2<0.48){
float2 there=cellFlow(int2(floor(toGrid(center+m)+0.5)),!backward);
if(length(m+there)>=motionTolerance(length(m))){found=true;adopted=m;}
}
}
}
[branch] if(bestCost<rawCost){
float2 polished=best;
[loop] for(int r=0;r<4;++r){
float2 m=best+float2(r==0?1:(r==1?-1:0),r==2?1:(r==3?-1:0));
float c=refineCost(own,center,step,m,backward);
if(c<bestCost){bestCost=c;polished=m;}
}
best=polished;
}
}
}
float detailHere=0;
[unroll] for(int t=0;t<16;++t)detailHere=max(detailHere,colorError(own[t],mean));
bool verified=bestCost<0.75*rawCost&&rawCost-bestCost>0.015&&bestCost<(consistent?0.05:(detailHere>0.08?0.015:-1.0));
bool adopt=!verified&&consistent&&found&&rawCost>0.08&&rawCost<9&&rawMatch.y<4;
float2 result=verified?best:(adopt?adopted:raw);
[branch] if(!verified&&!adopt&&rawCost<9){
float tolerance=motionTolerance(length(raw));
float3 sum=float3(0,0,0);
[unroll] for(int n=0;n<9;++n){
float2 v=cellFlow(cell+int2(n%3-1,n/3-1),backward);
if(length(v-raw)<tolerance)sum+=float3(v,1);
}
float2 mean=sum.xy/sum.z;
[branch] if(sum.z>=5&&length(mean-raw)>0.1){
float meanCost=refineCost(own,center,step,mean,backward);
if(meanCost<0.95*rawCost-0.001)result=mean;
}
}
return int2(round(result/FlowGain));
}
int2 RefineForward(Vertex v) : SV_Target { return refineCell(int2(floor(v.position.xy)),false); }
int2 RefineBackward(Vertex v) : SV_Target { return refineCell(int2(floor(v.position.xy)),true); }
float reliable(float2 q,bool backward) {
float2 v=cellFlow(int2(floor(toGrid(q)+0.5)),backward);
float2 w=cellFlow(int2(floor(toGrid(q+v)+0.5)),!backward);
float tolerance=motionTolerance(length(v));
return 1-smoothstep(tolerance,2.5*tolerance,length(v+w));
}
float occluder(float2 p,float2 motion,bool backward,float3 gain) {
float2 end=p+motion;
if(!inside(p)||!inside(end))return 0;
float cycle=probe(end,float2(0,0)-motion,!backward).support;
float tolerance=motionTolerance(length(motion));
float3 own=frameAt(p,backward);
float photo=nearestIn(own,end,!backward);
[branch] if(changed(gain))
photo=min(photo,nearestIn(backward?own/gain:own*gain,end,!backward));
return (1-smoothstep(tolerance,2.5*tolerance,cycle))*(1-smoothstep(0.04,0.16,photo));
}
struct Ranking { float2 m0; float2 m1; float2 m2; float c0; float c1; float c2; };
bool same(float2 a,float2 b) { return a.x==b.x&&a.y==b.y; }
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
struct Side { float score; float3 color; float2 occluderAt; float2 occluder; bool edge; float2 motion; };
struct Evaluation { float score; float confidence; float crossing; float flat; float3 color; Side fromCurrent; Side fromPrevious; };
float3 midpointColor(float2 p,float2 m) { return 0.5*(sharpAt(p-0.5*m,false)+sharpAt(p+0.5*m,true)); }
float wideContrast(float2 q) {
float3 c0=previousAt(q), c1=currentAt(q); float e0=0, e1=0;
[unroll] for(int k=0;k<4;++k){
float2 o=k==0?float2(3,0):(k==1?float2(-3,0):(k==2?float2(0,3):float2(0,-3)));
e0=max(e0,colorError(c0,previousAt(q+o)));e1=max(e1,colorError(c1,currentAt(q+o)));
}
return min(e0,e1);
}
Evaluation evaluate(float2 p,float2 m,float2 reference,float2 dominant,float2 secondMotion,bool twoSided,bool sides,float3 gain) {
float2 h=0.5*m, pa=p-h, pb=p+h;
float speed=length(m), tolerance=motionTolerance(speed);
float limit=1-smoothstep(160.0,256.0,speed);
bool insideA=inside(pa), insideB=inside(pb);
float different=2+0.03*speed;
Probe forward=probe(pa,m,false), backward=probe(pb,float2(0,0)-m,true);
float supportA=1-smoothstep(tolerance,2.5*tolerance,forward.support);
float supportB=1-smoothstep(tolerance,2.5*tolerance,backward.support);
float3 colorA=previousAt(pa), colorB=currentAt(pb);
float dominantLike=1-smoothstep(tolerance,2.5*tolerance,length(m-dominant));
float windowLike=max(dominantLike,1-smoothstep(tolerance,2.5*tolerance,length(m-secondMotion)));
float reliableA=1, reliableB=1;
[branch] if(windowLike>0&&min(supportA,supportB)<1){reliableA=reliable(pa,false);reliableB=reliable(pb,true);}
Evaluation r;
r.score=4; r.confidence=0; r.crossing=0; r.flat=0; r.color=0.5*(colorA+colorB);
if(twoSided&&insideA&&insideB){
float2 otherWindow=dominantLike>=0.5?secondMotion:dominant;
float smearA=1-smoothstep(tolerance,2.5*tolerance,length(forward.flow-otherWindow));
float smearB=1-smoothstep(tolerance,2.5*tolerance,length(backward.flow+otherWindow));
float separation=length(secondMotion-dominant);
smearA*=dominantLike*(separation>=4+0.1*length(dominant)?1.0:0.0);smearB*=dominantLike*(separation>=4+0.1*length(dominant)?1.0:0.0);
[branch] if(windowLike>0&&max(smearA,smearB)>0){
float2 ho=0.5*otherWindow;
float otherFails=inside(p-ho)&&inside(p+ho)?smoothstep(0.12,0.25,colorError(previousAt(p-ho)*gain,currentAt(p+ho))):1;
smearA*=otherFails;smearB*=otherFails;
}
float support=min(max(supportA,windowLike*max(1-reliableA,smearA)),max(supportB,windowLike*max(1-reliableB,smearB)))*limit;
[branch] if(speed<1.0){
float identity=colorError(colorA*gain,colorB);
support=max(support,max(supportA,supportB)*(1-smoothstep(0.02,0.05,identity))*limit);
}
float3 patch=matchPatchAxes(p,h,gain,colorA,colorB);
float cost=patch.x, thinCost=patch.z;
r.flat=(1-smoothstep(0.01,0.025,patch.y))*(1-smoothstep(0.03,0.06,cost))*limit;
r.confidence=(1-smoothstep(0.04,0.16,cost))*support;
float backgroundA=1-smoothstep(tolerance,2.5*tolerance,length(forward.flow-dominant));
float backgroundB=1-smoothstep(tolerance,2.5*tolerance,length(backward.flow+dominant));
float oneEnd=max(supportA*backgroundB,supportB*backgroundA)*limit*(1-smoothstep(0.02,0.06,thinCost))*0.9;
float minority=saturate((length(m-dominant)-2)*0.25);
float crossing=max(support*(1-smoothstep(0.06,0.25,thinCost)),oneEnd)*minority;
float textured=(1-smoothstep(0.03,0.07,thinCost))*smoothstep(0.08,0.2,patch.y)*limit;
float foreground=(1-smoothstep(tolerance,2.5*tolerance,length(m-secondMotion)))*(length(secondMotion-dominant)>=4+0.1*length(dominant)?1.0:0.0)*smoothstep(1.0,2.0,speed);
crossing=max(crossing,0.95*textured*minority*foreground);
float separate=length(m-dominant)>=4+0.1*length(dominant)?1.0:0.0;
float sparse=(1-smoothstep(0.015,0.035,thinCost))*smoothstep(0.08,0.2,patch.y)*limit*max(supportA,supportB)*separate*smoothstep(1.0,2.0,speed);
crossing=max(crossing,0.9*sparse*minority);
[branch] if(crossing>0){
float objectA=nearestIn(colorA*gain,pa+dominant,true), objectB=nearestIn(colorB/gain,pb-dominant,false);
crossing*=smoothstep(0.04,0.12,min(objectA,objectB));
[branch] if(speed>=2)crossing*=smoothstep(0.04,0.12,max(colorError(colorA*gain,currentAt(pa)),colorError(colorB/gain,previousAt(pb))));
}
r.confidence=max(r.confidence,crossing);r.crossing=crossing;
r.score=(1-r.confidence)+0.25*cost-0.6*crossing;
}
r.fromCurrent.score=r.fromPrevious.score=0; r.fromCurrent.color=r.fromPrevious.color=r.color;
r.fromCurrent.occluderAt=r.fromPrevious.occluderAt=p; r.fromCurrent.occluder=r.fromPrevious.occluder=float2(0,0);
r.fromCurrent.edge=r.fromPrevious.edge=false; r.fromCurrent.motion=r.fromPrevious.motion=m;
if(!sides)return r;
float hudA=0, hudB=0, nearA=0, nearB=0;
[branch] if(insideA&&insideB&&speed>=2){
float mismatch=smoothstep(0.08,0.16,colorError(colorA*gain,colorB));
[branch] if(mismatch>0){
int2 last=int2(ImageSize)-1;
nearA=OverlayNear.Load(int3(clamp(int2(floor(pa+0.5)),int2(0,0),last),0)).x;
nearB=OverlayNear.Load(int3(clamp(int2(floor(pb+0.5)),int2(0,0),last),0)).x;
hudA=mismatch*nearA*(1-nearB);hudB=mismatch*nearB*(1-nearA);
}
}
float staticA=0, staticB=0;
[branch] if(speed>=3){
float2 sa=insideA?matchPatchWith(pa,float2(0,0),gain,colorA,currentAt(pa)):float2(1,0), sb=insideB?matchPatchWith(pb,float2(0,0),gain,previousAt(pb),colorB):float2(1,0);
[branch] if(colorError(colorA*gain,colorB)>0.08){
[branch] if(sa.x<0.1&&sa.y<0.12)sa.y=max(sa.y,wideContrast(pa));
[branch] if(sb.x<0.1&&sb.y<0.12)sb.y=max(sb.y,wideContrast(pb));
}
staticA=(1-smoothstep(0.05,0.1,sa.x))*smoothstep(0.06,0.12,sa.y);
staticB=(1-smoothstep(0.05,0.1,sb.x))*smoothstep(0.06,0.12,sb.y);
}
float overlayHere=OverlayNear.Load(int3(clamp(int2(floor(p+0.5)),int2(0,0),int2(ImageSize)-1),0)).x;
float continued=dominantLike*(1-overlayHere);
[branch] if(windowLike==0&&(supportA>0||supportB>0)){reliableA=reliable(pa,false);reliableB=reliable(pb,true);}
float visibleB=max(supportB*max(reliableB,overlayHere),continued);
float visibleA=max(supportA*max(reliableA,overlayHere),continued);
float preference=1+0.1*continued;
r.fromCurrent.score=insideB?visibleB*preference*limit*(insideA?smoothstep(different,2*different,forward.deviation):supportA):0;
r.fromCurrent.score=max(r.fromCurrent.score,hudA*supportB*limit)*(1-staticB);
r.fromCurrent.color=colorB/sqrt(gain); r.fromCurrent.occluderAt=pa; r.fromCurrent.occluder=forward.other; r.fromCurrent.edge=!insideA||hudA>0.5; r.fromCurrent.motion=m;
r.fromPrevious.score=insideA?visibleA*preference*limit*(insideB?smoothstep(different,2*different,backward.deviation):supportB):0;
r.fromPrevious.score=max(r.fromPrevious.score,hudB*supportA*limit)*(1-staticA);
r.fromPrevious.color=colorA*sqrt(gain); r.fromPrevious.occluderAt=pb; r.fromPrevious.occluder=backward.other; r.fromPrevious.edge=!insideB||hudB>0.5; r.fromPrevious.motion=m;
return r;
}
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
contrast=min(contrast,max(max(colorError(previous,pLeft),colorError(previous,pRight)),
max(colorError(previous,pUp),colorError(previous,pDown))));
float structure=max(max(colorError(original.rgb-left,previous-pLeft),colorError(original.rgb-right,previous-pRight)),
max(colorError(original.rgb-up,previous-pUp),colorError(original.rgb-down,previous-pDown)));
bool fixedDetail=identity<0.02||(structure<min(0.1,0.3*contrast));
[branch] if(fixedDetail&&contrast>0.12){
Probe still=probe(p,float2(0,0),true), stillForward=probe(p,float2(0,0),false);
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
float2 OverlayGrow(Vertex v) : SV_Target {
int2 c=int2(floor(v.position.xy)), m=int2(ImageSize)-1;
float r=0, n=0;
[unroll] for(int y=-2;y<=2;++y)
[unroll] for(int x=-2;x<=2;++x){
float o=OverlayRaw.Load(int3(clamp(c+int2(x,y),int2(0,0),m),0));
r=max(r,o); n+=o>0.5?1:0;
}
return float2(r,min(n,2.0));
}
struct Candidates { float2 a0; float2 a1; float2 a2; float2 a3; float2 b0; float2 b1; float2 b2; float2 b3; float4 p0; float4 p1; float4 p2; float4 p3; };
Candidates gatherCandidates(int2 cellA,int2 cellB,int2 cellP,int2 maximum) {
Candidates c;
c.a0=cellFlow(cellA,false); c.a1=cellFlow(cellA+int2(1,0),false); c.a2=cellFlow(cellA+int2(0,1),false); c.a3=cellFlow(cellA+int2(1,1),false);
c.b0=float2(0,0)-cellFlow(cellB,true); c.b1=float2(0,0)-cellFlow(cellB+int2(1,0),true);
c.b2=float2(0,0)-cellFlow(cellB+int2(0,1),true); c.b3=float2(0,0)-cellFlow(cellB+int2(1,1),true);
c.p0=Projected.Load(int3(clamp(cellP,int2(0,0),maximum),0)); c.p1=Projected.Load(int3(clamp(cellP+int2(1,0),int2(0,0),maximum),0));
c.p2=Projected.Load(int3(clamp(cellP+int2(0,1),int2(0,0),maximum),0)); c.p3=Projected.Load(int3(clamp(cellP+int2(1,1),int2(0,0),maximum),0));
return c;
}
float2 candidateMotion(int k,Candidates c) {
int j=k&3;
float2 a=j==0?c.a0:(j==1?c.a1:(j==2?c.a2:c.a3)), b=j==0?c.b0:(j==1?c.b1:(j==2?c.b2:c.b3));
float4 pair=j==0?c.p0:(j==1?c.p1:(j==2?c.p2:c.p3));
return k<4?a:(k<8?b:(k<16?((k&4)!=0?float2(pair.z,pair.w):float2(pair.x,pair.y)):float2(0,0)));
}
float4 synthesizeColor(Vertex v,out float4 choice) {
choice=float4(0,0,3,0);
float2 p=v.position.xy-0.5, a=p, b=p;
float2 a1=p-0.5*flowAt(a,false), b1=p-0.5*flowAt(b,true);
a=p-0.5*flowAt(a1,false); b=p-0.5*flowAt(b1,true);
[branch] if(max(length(a-a1),length(b-b1))>0.01){a=p-0.5*flowAt(a,false);b=p-0.5*flowAt(b,true);}
float4 original=Current.SampleLevel(LinearClamp,v.uv,0);
int2 maximum=gridMaximum();
int2 cellA=int2(floor(toGrid(a))), cellB=int2(floor(toGrid(b)));
int2 cellP=int2(floor(toGrid(p)));
Candidates cells=gatherCandidates(cellA,cellB,cellP,maximum);
float2 ta=frac(toGrid(a)), tb=frac(toGrid(b));
float2 forwardMotion=lerp(lerp(cells.a0,cells.a1,ta.x),lerp(cells.a2,cells.a3,ta.x),ta.y);
float2 backwardMotion=lerp(lerp(cells.b0,cells.b1,tb.x),lerp(cells.b2,cells.b3,tb.x),tb.y);
float2 reference=0.5*(forwardMotion+backwardMotion);
float4 window=dominantAt(p);
bool windowValid=window.x<0.5*invalidMotion;
float2 dominant=windowValid?window.xy:reference, secondMotion=windowValid?float2(window.z,window.w):reference;
float spread=0;
[loop] for(int s0=0;s0<16;++s0)spread=max(spread,length(candidateMotion(s0,cells)-reference));
float overlayFlag=OverlayRaw.Load(int3(int2(floor(v.position.xy)),0))>0.5?2:0;
float3 gain=float3(1,1,1);
bool steadyMotion=false;
[branch] if(spread<8){
Evaluation steady=evaluate(p,reference,reference,dominant,secondMotion,true,false,gain);
steadyMotion=steady.confidence>0.95&&nearestMatch(original.rgb,p-reference)<0.08;
[branch] if(spread>=1&&steadyMotion){
bool other=steady.crossing>0;
[loop] for(int f=0;f<18&&!other;++f){
float2 m=f<16?candidateMotion(f,cells):(f==16?dominant:secondMotion);
[branch] if(length(m-reference)>=1&&length(m)<256){
float3 c0=previousAt(p-0.5*m), c1=currentAt(p+0.5*m);
other=colorError(c0,c1)<0.08&&colorError(0.5*(c0+c1),steady.color)>0.06;
}
}
steadyMotion=!other;
}
}
[branch] if(spread>=1&&!steadyMotion){
float2 h=0.5*reference;
float2 patch=matchPatch(p,h,float3(1,1,1));
[branch] if(patch.y<0.02&&patch.x<0.05&&inside(p-h)&&inside(p+h)&&nearestMatch(original.rgb,p-reference)<0.08){
float3 flat=0.5*(previousAt(p-h)+currentAt(p+h));
bool other=false;
[loop] for(int f=0;f<16&&!other;++f){
float2 m=candidateMotion(f,cells);
[branch] if(length(m-reference)>=1&&length(m)<256){
float3 c0=previousAt(p-0.5*m), c1=currentAt(p+0.5*m);
other=colorError(c0,c1)<0.08&&colorError(0.5*(c0+c1),flat)>0.06;
}
}
steadyMotion=!other;
}
}
[branch] if(!steadyMotion){
gain=exposureGain(p,reference);
[branch] if(spread<1&&changed(gain)){
Evaluation steady=evaluate(p,reference,reference,dominant,secondMotion,true,false,gain);
steadyMotion=steady.confidence>0.95&&explained(original.rgb,gain,p-reference)<0.08;
}
}
float4 result=float4(0,0,0,0);
[branch] if(steadyMotion){
choice=float4(reference,0,1);
float3 steadyColor=midpointColor(p,reference);
float movingFlag=0;
[branch] if(overlayFlag==0&&length(reference)>=2&&colorError(steadyColor,original.rgb)>0.1&&colorError(previousAt(p),original.rgb)<0.02){
if(movesHere(p,reference,gain))movingFlag=4;
}
[branch] if(overlayFlag==0&&movingFlag==0&&OverlayNear.Load(int3(int2(floor(v.position.xy)),0)).x>0.5){
float3 previousHere=previousAt(p);
if(colorError(previousHere,original.rgb)>=0.02&&movesBesideOverlay(p,reference,original.rgb,previousHere))movingFlag=4;
}
result=float4(steadyColor,1+overlayFlag+movingFlag);
}
else{
Ranking ranking;
ranking.m0=ranking.m1=ranking.m2=float2(0,0); ranking.c0=ranking.c1=ranking.c2=1e9;
float2 deviating=float2(0,0); float deviatingCost=1e9;
[loop] for(int k=0;k<19;++k){
float2 m=k<17?candidateMotion(k,cells):(k==17?dominant:secondMotion);
float2 h=0.5*m;
if(length(m)<256&&inside(p-h)&&inside(p+h)){
float c=colorError(previousAt(p-h)*gain,currentAt(p+h));
ranking=rank(ranking,m,c);
if((k<16||k==18)&&length(m-dominant)>3&&c<deviatingCost){deviating=m;deviatingCost=c;}
}
}
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
[loop] for(int n=0;n<9;++n){
float2 m=forwardMotion; bool ranked=n<4||n==8;
if(n==0)m=ranking.m0; else if(n==1)m=ranking.m1; else if(n==2)m=ranking.m2; else if(n==3)m=deviating;
else if(n==5)m=backwardMotion;
else if(n==6)m=ta.y<0.5?(ta.x<0.5?cells.a0:cells.a1):(ta.x<0.5?cells.a2:cells.a3);
else if(n==7)m=tb.y<0.5?(tb.x<0.5?cells.b0:cells.b1):(tb.x<0.5?cells.b2:cells.b3);
else if(n==8)m=dominant;
float rankedCost=n==0?ranking.c0:(n==1?ranking.c1:(n==2?ranking.c2:(n==3?deviatingCost:0)));
if(n==8&&((ranking.c0<1e8&&length(m-ranking.m0)<1)||(ranking.c1<1e8&&length(m-ranking.m1)<1)||(ranking.c2<1e8&&length(m-ranking.m2)<1)))rankedCost=1e9;
bool evaluated0=ranking.c0<1e8, evaluated1=ranking.c1<1e8, evaluated2=ranking.c2<1e8, evaluated3=deviatingCost<1e8;
bool repeat=(n>=3&&n!=8)&&((evaluated0&&same(m,ranking.m0))||(evaluated1&&same(m,ranking.m1))||(evaluated2&&same(m,ranking.m2)));
repeat=repeat||(n>=4&&n!=8&&evaluated3&&same(m,deviating))||((n==5||n==6||n==7)&&same(m,forwardMotion));
repeat=repeat||((n==6||n==7)&&same(m,backwardMotion))||(n==7&&same(m,(ta.y<0.5?(ta.x<0.5?cells.a0:cells.a1):(ta.x<0.5?cells.a2:cells.a3))));
if(repeat)rankedCost=1e9;
if(rankedCost<1e8){
Evaluation e=evaluate(p,m,reference,dominant,secondMotion,ranked,true,gain);
if(ranked&&e.score<bestScore){bestScore=e.score;bestConfidence=e.confidence;bestCrossing=e.crossing;bestColor=e.color;bestMotion=m;}
if(e.flat>bestFlat){bestFlat=e.flat;flatMotion=m;}
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
float oneSided=min(1.0,max(fromCurrent.score,fromPrevious.score));
bool useCurrent=fromCurrent.score>=fromPrevious.score;
float weightB=bestConfidence, weightO=(1-bestConfidence)*oneSided*(1-bestFlat);
[branch] if(weightB>0.001)bestColor=midpointColor(p,bestMotion);
float3 oneColor=useCurrent?fromCurrent.color:fromPrevious.color;
[branch] if(weightO>0.001)oneColor=useCurrent?sharpAt(p+0.5*fromCurrent.motion,true)/sqrt(gain):sharpAt(p-0.5*fromPrevious.motion,false)*sqrt(gain);
float weightF=0; float3 flatColor=original.rgb;
[branch] if(bestFlat>0.001){
flatColor=0.5*(previousAt(p-0.5*flatMotion)*sqrt(gain)+currentAt(p+0.5*flatMotion)/sqrt(gain));
weightF=(1-weightB-weightO)*bestFlat*smoothstep(0.08,0.16,colorError(original.rgb,flatColor));
}
float weightR=0; float3 refColor=original.rgb; float2 refMotion=reference;
float nearOverlay=OverlayNear.Load(int3(int2(floor(v.position.xy)),0)).x;
[branch] if(weightB+weightO+weightF<0.999&&length(reference)>=1&&nearOverlay<0.5){
float2 hr=0.5*reference; float refCost=inside(p-hr)&&inside(p+hr)?matchCost(p,hr,gain):9;
[branch] if(refCost>0.1){
[loop] for(int r=0;r<3;++r){
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
refColor=0.5*(ra+rb); refMotion=2*hr;
weightR=(1-weightB-weightO-weightF)*smoothstep(1.0,3.0,2*length(hr))*(1-smoothstep(0.1,0.25,refCost));
}
}
float valid=weightB+weightO+weightF+weightR;
float3 color=valid>0.001?(weightB*bestColor+weightO*oneColor+weightF*flatColor+weightR*refColor)/valid:original.rgb;
float here=explained(original.rgb,gain,p);
float keep=smoothstep(0.08,0.2,here);
keep*=smoothstep(0.08,0.2,explained(original.rgb,gain,p-ranking.m0));
if(deviatingCost<1e8)keep*=smoothstep(0.08,0.2,explained(original.rgb,gain,p-deviating));
[loop] for(int j=0;j<4;++j){
float2 u=cellFlow(cellP+int2(j&1,j>>1),true), q=p+u;
float uTolerance=motionTolerance(length(u));
float revealed=inside(q)?smoothstep(uTolerance,2.5*uTolerance,
length(cellFlow(int2(floor(toGrid(q)+0.5)),false)+u)):1;
if(inside(q))revealed=max(revealed,OverlayNear.Load(int3(int2(floor(q+0.5)),0)).x);
keep*=smoothstep(0.08,0.2,explained(original.rgb,gain,q))*(1-revealed);
}
[branch] if(keep>0&&windowValid){
[loop] for(int w=0;w<2;++w){
float2 u=float2(0,0)-(w==0?dominant:secondMotion), q=p+u;
float uTolerance=motionTolerance(length(u));
[branch] if(length(u)>=1&&inside(q))keep*=1-smoothstep(uTolerance,2.5*uTolerance,length(cellFlow(int2(floor(toGrid(q)+0.5)),false)+u));
}
}
float3 left=currentAt(p-float2(1,0)), right=currentAt(p+float2(1,0));
float3 up=currentAt(p-float2(0,1)), down=currentAt(p+float2(0,1));
float thin=max(smoothstep(0.08,0.16,min(colorError(original.rgb,left),colorError(original.rgb,right))),
smoothstep(0.08,0.16,min(colorError(original.rgb,up),colorError(original.rgb,down))));
float stay=min(colorError(original.rgb,previousAt(p)),colorError(original.rgb/gain,previousAt(p)));
keep=max(keep,(1-smoothstep(0.03,0.08,stay))*smoothstep(0.1,0.2,colorError(color,original.rgb))*thin);
[branch] if(length(bestMotion)>=3&&weightB>0.5&&colorError(color,original.rgb)>0.1){
float still=0;
float here0=colorError(previousAt(p),original.rgb);
here0=min(here0,min(min(colorError(previousAt(p+float2(1,0)),original.rgb),colorError(previousAt(p-float2(1,0)),original.rgb)),
min(colorError(previousAt(p+float2(0,1)),original.rgb),colorError(previousAt(p-float2(0,1)),original.rgb))));
float background=1-smoothstep(0.02,0.05,here0);
float edge=0;
[loop] for(int e=0;e<8;++e){
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
[branch] if(keep<0.99&&colorError(color,original.rgb)>0.1&&colorError(previousAt(p),original.rgb)<0.04&&wideContrast(p)>0.2){
float glyph=0;
[loop] for(int k=0;k<8;++k){
float2 d=k<4?float2((k&1)!=0?1.0:-1.0,(k&2)!=0?1.0:-1.0)*0.7071:float2(k==4?1.0:(k==5?-1.0:0.0),k==6?1.0:(k==7?-1.0:0.0));
float2 q=p+d*(3*FlowBlock);
float2 f=flowAt(q,false), bk=flowAt(q,true);
float speed=length(f);
if(inside(q)&&speed>2&&length(f+bk)<motionTolerance(speed)&&explained(original.rgb,gain,p-f)>0.1)glyph=1;
}
keep=max(keep,glyph);
}
color=lerp(color,original.rgb,keep);
float fading=0;
[branch] if(windowValid&&length(dominant)<1&&length(reference)<1){
float3 a0=previousAt(p), b0=original.rgb;
[branch] if(colorError(a0,b0)>0.06){
float3 sa=a0, sb=b0, na[4], nb[4];
[unroll] for(int q=0;q<4;++q){
float2 o=q==0?float2(1,0):(q==1?float2(-1,0):(q==2?float2(0,1):float2(0,-1)));
na[q]=previousAt(p+o); nb[q]=currentAt(p+o); sa+=na[q]; sb+=nb[q];
}
float g=(dot(sa,float3(1,1,1))+0.03)/(dot(sb,float3(1,1,1))+0.03);
float residual=colorError(a0,b0*g);
[unroll] for(int r=0;r<4;++r)residual=max(residual,colorError(na[r],nb[r]*g));
[branch] if(residual<0.035){
[unroll] for(int f=0;f<4;++f){
float2 o=f==0?float2(6,0):(f==1?float2(-6,0):(f==2?float2(0,6):float2(0,-6)));
float3 fa=previousAt(p+o), fb=currentAt(p+o);
residual=max(residual,colorError(fa,fb*g)+0.5*(1-smoothstep(0.03,0.06,colorError(fa,fb))));
}
}
fading=(1-smoothstep(0.015,0.035,residual))*smoothstep(0.06,0.12,colorError(a0,b0));
[branch] if(fading>0)color=lerp(color,0.5*(a0+b0),fading);
}
}
float translucent=0;
[branch] if(windowValid&&length(dominant)>=2&&keep<0.99){
float2 mT=dominant;
[branch] if(inside(p-mT)&&inside(p+mT)&&explained(original.rgb,gain,p-bestMotion)>0.05&&nearestIn(previousAt(p),p+bestMotion,true)>0.05){
float3 previousHere=previousAt(p), ahead=currentAt(p+mT), behind=previousAt(p-mT);
float3 d0=previousHere-original.rgb, d1=ahead-behind;
float den=dot(d1,d1);
[branch] if(den>0.03){
float k=saturate(dot(d0,d1)/den);
float residual=colorError(d0,k*d1);
float3 sceneA=previousAt(p-0.5*mT), sceneB=currentAt(p+0.5*mT);
float sceneCost=colorError(sceneA,sceneB);
translucent=(1-smoothstep(0.015,0.035,residual))*(1-smoothstep(0.04,0.08,sceneCost))*smoothstep(0.05,0.15,k)*(1-smoothstep(0.85,0.95,k));
[branch] if(translucent>0)color=lerp(color,0.5*(previousHere+original.rgb)+k*(0.5*(sceneA+sceneB)-0.5*(ahead+behind)),translucent);
}
}
}
bool separateCrossing=!windowValid||length(bestMotion-dominant)>=4+0.1*length(dominant);
float crossingFlag=((bestCrossing>0.5&&weightB>0.5*valid&&keep<0.5&&separateCrossing)||translucent>0.5)?4:0;
[branch] if(crossingFlag==0&&overlayFlag==0&&keep<0.5&&weightB>0.5*valid&&bestConfidence>0.9&&length(bestMotion)>=2&&colorError(color,original.rgb)>0.1&&colorError(previousAt(p),original.rgb)<0.02){
if(movesHere(p,bestMotion,gain))crossingFlag=4;
}
[branch] if(crossingFlag==0&&overlayFlag==0&&keep<0.5&&weightB>0.5*valid&&nearOverlay>0.5){
float3 previousHere=previousAt(p);
if(colorError(previousHere,original.rgb)>=0.02&&movesBesideOverlay(p,bestMotion,original.rgb,previousHere))crossingFlag=4;
}
float wb=(1-keep)*weightB, wo=(1-keep)*weightO, wf=(1-keep)*weightF, wr=(1-keep)*weightR;
float top=max(max(wb,wo),max(max(wf,wr),keep));
if(top>0.05){
if(top==wb)choice=float4(bestMotion,0,top);
else if(top==wo)choice=useCurrent?float4(fromCurrent.motion,2,top):float4(fromPrevious.motion,1,top);
else if(top==wf)choice=float4(flatMotion,0,top);
else if(top==wr)choice=float4(refMotion,0,top);
else choice=float4(0,0,2,top);
}
float confidenceOut=max(max(max(valid,keep),translucent),fading);
float2 sideMotion=useCurrent?fromCurrent.motion:fromPrevious.motion;
float sideTolerance=motionTolerance(length(sideMotion));
bool sideTop=(1-keep)*weightO>max(max((1-keep)*weightB,(1-keep)*weightF),max((1-keep)*weightR,keep));
bool foreignSide=sideTop&&length(sideMotion-dominant)>=sideTolerance&&length(sideMotion-secondMotion)>=sideTolerance;
if(windowValid&&!foreignSide&&confidenceOut>0.001)confidenceOut=saturate(0.2+confidenceOut*2.3333);
result=float4(color,confidenceOut+overlayFlag+crossingFlag);
}
return result;
}
struct SynthesisOutput { float4 color : SV_Target0; float4 choice : SV_Target1; };
SynthesisOutput Synthesize(Vertex v) {
SynthesisOutput o; o.color=synthesizeColor(v,o.choice); return o;
}
float confidenceOf(float w) { w=w>=3.5?w-4:w; return w>=1.5?w-2:w; }
bool overlayOf(float w) { w=w>=3.5?w-4:w; return w>=1.5; }
float4 Resolve(Vertex v) : SV_Target {
float4 original=Current.SampleLevel(LinearClamp,v.uv,0);
int2 here=int2(floor(v.position.xy)), last=int2(ImageSize)-1;
float4 candidate=Reprojection.Load(int3(here,0));
float centerValid=confidenceOf(candidate.w);
float crossing=candidate.w>=3.5?1:0;
float support=0, overlays=OverlayNear.Load(int3(here,0)).y;
[unroll] for(int y=-1;y<=1;++y)
[unroll] for(int x=-1;x<=1;++x)
support+=confidenceOf(x==0&&y==0?candidate.w:Reprojection.Load(int3(clamp(here+int2(x,y),int2(0,0),last),0)).w);
float3 previousHere=Previous.SampleLevel(LinearClamp,v.uv,0).rgb;
float3 o1=Current.SampleLevel(LinearClamp,v.uv+float2(1,0)*InvImageSize,0).rgb, o2=Current.SampleLevel(LinearClamp,v.uv-float2(1,0)*InvImageSize,0).rgb;
float3 o3=Current.SampleLevel(LinearClamp,v.uv+float2(0,1)*InvImageSize,0).rgb, o4=Current.SampleLevel(LinearClamp,v.uv-float2(0,1)*InvImageSize,0).rgb;
float3 q1=Previous.SampleLevel(LinearClamp,v.uv+float2(1,0)*InvImageSize,0).rgb, q2=Previous.SampleLevel(LinearClamp,v.uv-float2(1,0)*InvImageSize,0).rgb;
float3 q3=Previous.SampleLevel(LinearClamp,v.uv+float2(0,1)*InvImageSize,0).rgb, q4=Previous.SampleLevel(LinearClamp,v.uv-float2(0,1)*InvImageSize,0).rgb;
float confidence=smoothstep(0.2,0.9,min(centerValid,support*(1.25/9)));
confidence*=1-smoothstep(0.25,1.5,overlays)*(1-crossing);
float nearby=min(min(colorError(q1,o1),colorError(q2,o2)),min(colorError(q3,o3),colorError(q4,o4)));
float stationary=1-smoothstep(0.004,0.016,max(colorError(previousHere,original.rgb),nearby));
float detail=smoothstep(0.04,0.1,max(max(colorError(original.rgb,o1),colorError(original.rgb,o2)),max(colorError(original.rgb,o3),colorError(original.rgb,o4))));
detail=max(detail,1-smoothstep(0.05,0.15,colorError(candidate.rgb,original.rgb)));
confidence*=1-stationary*detail*(1-crossing);
float3 fallback=original.rgb;
[branch] if(confidence<0.999){
float local=0;
[unroll] for(int k=0;k<4;++k){
float2 o=(k==0?float2(2,0):(k==1?float2(-2,0):(k==2?float2(0,2):float2(0,-2))))*InvImageSize;
local=max(local,max(colorError(Current.SampleLevel(LinearClamp,v.uv+o,0).rgb,original.rgb),
colorError(Previous.SampleLevel(LinearClamp,v.uv+o,0).rgb,previousHere)));
}
float soft=1-smoothstep(0.06,0.15,local);
float close=1-smoothstep(0.25,0.55,colorError(previousHere,original.rgb));
fallback=lerp(original.rgb,0.5*(previousHere+original.rgb),soft*close*(1-stationary)*(1-smoothstep(0.25,1.5,overlays)));
}
return float4(lerp(fallback,candidate.rgb,confidence),original.w);
}
float4 Coherence(Vertex v) : SV_Target {
int2 here=int2(floor(v.position.xy)), last=int2(ImageSize)-1;
float2 p=v.position.xy-0.5;
float4 result=Reprojection.Load(int3(here,0));
float4 own=Choice.Load(int3(here,0));
float weight[4]={0,0,0,0}; float2 sum[4]={float2(0,0),float2(0,0),float2(0,0),float2(0,0)}; float kind[4]={0,0,0,0};
float total=0, ownVotes=0, meanWeight=0; float2 meanMotion=float2(0,0);
bool undecided=own.z>2.5;
float4 window=undecided?dominantAt(p):float4(invalidMotion,invalidMotion,0,0);
bool windowValid=window.x<0.5*invalidMotion;
float2 hw=windowValid?0.5*window.xy:float2(0,0);
float ea=0, eb=0, en=0;
[loop] for(int i=0;i<32;++i){
uint u=uint(i<12?i:i+1);
int2 o=i<24?int2(int(u%5)-2,int(u/5)-2):(i<28?int2(i==24?4:(i==25?-4:0),i==26?4:(i==27?-4:0)):int2((i&1)!=0?3:-3,(i&2)!=0?3:-3));
float4 c=Choice.Load(int3(clamp(here+o,int2(0,0),last),0));
if(c.z>2.5||c.w<=0)continue;
float w=c.w*(i<24?1.0:0.5); total+=w;
if(c.z<0.5){meanMotion+=c.xy*w;meanWeight+=w;}
float tolerance=1.5+0.05*length(c.xy);
[branch] if(undecided&&windowValid&&i<24&&c.z<0.5&&length(c.xy-window.xy)<tolerance){
float2 q=p+float2(o);
float3 n=Reprojection.Load(int3(clamp(here+o,int2(0,0),last),0)).rgb;
ea+=colorError(previousAt(q-hw),n); eb+=colorError(currentAt(q+hw),n); en+=1;
}
if(own.z<2.5&&own.z==c.z&&length(own.xy-c.xy)<tolerance)ownVotes+=w;
bool placed=false;
[unroll] for(int k=0;k<4;++k){
if(!placed&&weight[k]>0&&kind[k]==c.z&&length(sum[k]-c.xy*weight[k])<tolerance*weight[k]){weight[k]+=w;sum[k]+=c.xy*w;placed=true;}
}
[unroll] for(int e=0;e<4;++e){
if(!placed&&weight[e]==0){weight[e]=w;sum[e]=c.xy*w;kind[e]=c.z;placed=true;}
}
}
int best=0;
[unroll] for(int b=1;b<4;++b)if(weight[b]>weight[best])best=b;
if(total<=0.001||weight[best]<=0)return result;
float2 m=sum[best]/weight[best]; float side=kind[best];
float fraction=weight[best]/total, ownFraction=own.z<2.5?ownVotes/total:0;
float disagreement=smoothstep(0.35,0.6,1-fraction)*(1-smoothstep(0.3,0.5,ownFraction));
float3 previousHere=Previous.Load(int3(here,0)).rgb, currentHere=Current.Load(int3(here,0)).rgb;
if(own.z<2.5&&own.z!=1&&length(own.xy)<1)disagreement*=smoothstep(0.03,0.06,colorError(previousHere,currentHere));
[branch] if(disagreement>0&&!overlayOf(result.w)&&result.w<3.5){
float3 blurred=float3(0,0,0), low=float3(1e9,1e9,1e9), high=float3(-1e9,-1e9,-1e9); float blurWeight=0;
[unroll] for(int y=-2;y<=2;++y)
[unroll] for(int x=-2;x<=2;++x){
float4 c=Reprojection.Load(int3(clamp(here+int2(x,y),int2(0,0),last),0));
float w=(3-abs(x)*0.5-abs(y)*0.5);
blurred+=c.rgb*w; blurWeight+=w; low=min(low,c.rgb); high=max(high,c.rgb);
}
blurred=blurred/blurWeight;
float spread=max(high.x-low.x,max(high.y-low.y,high.z-low.z));
float soften=disagreement*smoothstep(0.08,0.2,spread);
[branch] if(soften>0&&meanWeight>0.5*total){
float2 mean=meanMotion/meanWeight;
if(inside(p-0.5*mean)&&inside(p+0.5*mean))blurred=lerp(midpointColor(p,mean),blurred,0.35);
}
result.rgb=lerp(result.rgb,blurred,soften);
}
if(undecided){
float tolerance=1.5+0.05*length(window.xy);
[branch] if(windowValid&&en>=3&&fraction>=0.6&&side<1.5&&length(m-window.xy)<tolerance&&!overlayOf(result.w)&&OverlayNear.Load(int3(here,0)).x<0.5){
ea=inside(p-hw)?ea/en:9; eb=inside(p+hw)?eb/en:9;
float3 fill=ea<=eb?sharpAt(p-hw,false):sharpAt(p+hw,true);
float fit=1-smoothstep(0.06,0.15,min(ea,eb));
float u=smoothstep(0.6,0.8,fraction)*fit;
result=float4(lerp(result.rgb,fill,u),result.w-confidenceOf(result.w)+lerp(confidenceOf(result.w),float(0.9),u));
}
return result;
}
if(own.z==side&&length(own.xy-m)<1.5+0.05*length(m)){
[branch] if(own.z<0.5&&length(own.xy-m)>0.75&&!overlayOf(result.w)&&result.w<3.5){
float2 h=0.5*m, g=0.5*own.xy;
[branch] if(inside(p-h)&&inside(p+h)&&inside(p-g)&&inside(p+g)){
float meanCost=colorError(previousAt(p-h),currentAt(p+h)), ownCost=colorError(previousAt(p-g),currentAt(p+g));
float u=(1-smoothstep(0.0,0.03,meanCost-ownCost))*own.w;
[branch] if(u>0.001)result.rgb=lerp(result.rgb,midpointColor(p,m),u);
}
}
return result;
}
float t=smoothstep(0.35,0.55,fraction)*(1-smoothstep(0.12,0.3,ownFraction));
if(result.w>=3.5&&ownFraction>=0.1)t=0;
if(overlayOf(result.w))t=0;
[branch] if(t>0&&own.z<2.5&&own.z!=1&&length(own.xy)<1){
t*=smoothstep(0.03,0.06,colorError(previousHere,currentHere));
}
[branch] if(t>0&&side<0.5){
float2 h=0.5*m;
float cost=inside(p-h)&&inside(p+h)?colorError(previousAt(p-h),currentAt(p+h)):1;
t*=1-smoothstep(0.12,0.25,cost);
[branch] if(own.z<0.5){
float2 g=0.5*own.xy;
float ownCost=inside(p-g)&&inside(p+g)?colorError(previousAt(p-g),currentAt(p+g)):1;
t*=1-smoothstep(0.04,0.1,cost-ownCost);
}
}
if(t<=0.001)return result;
float3 color=side<0.5?midpointColor(p,m):(side<1.5?sharpAt(p-0.5*m,false):sharpAt(p+0.5*m,true));
return float4(lerp(result.rgb,color,t),result.w);
}
float4 Blit(Vertex v) : SV_Target { return Previous.Load(int3(int2(floor(v.position.xy)),0)); }
float srgbToLinear(float c) { return c<=0.04045?c/12.92:pow(abs((c+0.055)/1.055),2.4); }
float4 BlitSrgb(Vertex v) : SV_Target {
float4 c=Previous.Load(int3(int2(floor(v.position.xy)),0));
return float4(srgbToLinear(c.x),srgbToLinear(c.y),srgbToLinear(c.z),c.w);
}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              