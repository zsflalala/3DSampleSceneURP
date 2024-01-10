Shader "ShengFu/RayMarchDrawSphere"
{
    Properties
    {
        _MainTex("MainTex",2D) = "white" {}
        _SphereSDFRadius("SphereRadius",float) = 0.5
        _BaseColor("BaseColor",Color) = (1.0, 1.0, 1.0, 1.0) 
    }
    SubShader
    {
        Tags 
        {
            "RenderPipeline"="UniversalRenderPipeline"
        }
        
        Pass
        {
            Name "MyForwardPass"
            Tags
            {
                "LightMode"="UniversalForward"
                "RenderType"="Overlay"  // 叠加摄像机
            }
            
            ZTest Always
            ZWrite On
        
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            
            CBUFFER_START(UnityPerMaterial)
            float  _SphereSDFRadius;
            float4 _BaseColor;
            float4 _MainTex_ST;
            float4 _MainTex_TexelSize;
            CBUFFER_END

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            struct VertexInput
            {
                float4 postionOS : POSITION;
                float2 texcoord  : TEXCOORD0;
            };

            struct VertexOutput
            {
                float4 postionCS : SV_POSITION;
                float2 texcoord  : TEXCOORD0;
            };

            // 球形SDF
            float sdfPhere(float3 pos,float s){
                return length(pos) - s;
            }

            // 甜甜圈托马斯环SDF
            float sdfTorus(float3 p){
                float2 t = float2(1.0,0.4); // 定义内外半径
                // t.x *= abs(sin(_Time.y));
                // t.y *= abs(cos(_Time.y));
                float2 q = float2(length(p.xz) - t.x, p.y);
                return length(q) - t.y;
            }

            // 菱形体SDF
            float sdfOctahedron(float3 p){
                p = abs(p);
                return (p.x + p.y + p.z - 2) * 0.57735027;
            }

            float getSDFdis(float3 pos){
                return sdfPhere(pos,_SphereSDFRadius); // 计算球形sdf
                // return sdfTorus(pos); // 计算托马斯sdf
                // return lerp(sdfTorus(pos),sdfPhere(pos,_SphereSDFRadius),abs(sin(_Time.y))); // 混合两个sdf
                // return lerp(sdfTorus(pos),sdfOctahedron(pos),abs(_Time.y)); // 混合菱形和甜甜圈 
            }

            float getNormal(float3 pos){
                // 计算三个方向的偏导数
                float delta = 0.01;
                float dx = ( getSDFdis(pos + float3(delta, 0.0,  0.0 )) - getSDFdis(pos) ) / delta;
                float dy = ( getSDFdis(pos + float3(0.0,  delta, 0.0 )) - getSDFdis(pos) ) / delta;
                float dz = ( getSDFdis(pos + float3(0.0,  0.0,  delta)) - getSDFdis(pos) ) / delta;
                return normalize(float3(dx,dy,dz));
            }

            float GetLight(float3 point1){
                float3 normal = getNormal(point1);
                // float3 LightDir = normalize(GetMainLight().direction);
                // float3 LightDir = _MainLightPosition.xyz;
                float3 LightDir = normalize(_MainLightPosition - point1);
                float dif = clamp(dot(normal,LightDir),0,1);// * 0.5 + 0.5; 
                return dif;
            }

            float3 RayMarch(float3 camPos,float3 ray){
                int MAX_STEP = 64;
                float MAX_DIST = 100.0;
                float SURFACE_DIST = 0.02;
                float distanceTotal = 0.0;
                float3 marchPos = float3(0.0, 0.0, 0.0);
                for (int i = 0;i < MAX_STEP;i++){
                    marchPos = camPos + ray * distanceTotal; // 当前射线步进的位置
                    float dis = getSDFdis(marchPos);         // 该位置距离球面的距离
                    if (dis < SURFACE_DIST || distanceTotal > MAX_DIST){   // 如果步进的总距离超过20，说明没找到球表面，退出循环
                        break;                               // 或者步进点到球表面距离小于0.02，说明找到球表面，退出循环
                    }
                    distanceTotal += dis;
                }
                // 循环结束输出的distanceTotal要么是找到了球表面，要么是超过最大距离也没找到
                // return distanceTotal;
                float3 color = float3(1.0, 0.0, 0.0);
                if (getSDFdis(marchPos) < SURFACE_DIST){
                    color = float3(1.0, 1.0, 0.0);
                    // float dif = GetLight(marchPos);
                    // return float3(dif,0,0);
                }
                return color;
            }
            
            VertexOutput vert (VertexInput v)
            {
                VertexOutput o = (VertexOutput)0; 
                o.postionCS = TransformObjectToHClip(v.postionOS);
                o.texcoord = v.texcoord;
                return o;
            }

            float4 frag (VertexOutput i) : COLOR
            {
                float aspect = _ScreenParams.y / _ScreenParams.x; // 屏幕宽纵比
                float2 uv = i.texcoord * 2 - 1;
                uv.y *= aspect;
                float3 rayVS = normalize(float3(uv,2));
                float3 camPosWS = _WorldSpaceCameraPos;
                // 计算 相机空间 的三个轴的朝向
                float3 VScoordZ = -normalize(camPosWS); // 相机空间Z轴
                float3 VScoordX = cross(float3(0.0, 1.0, 0.0), VScoordZ); // 左手定理判断叉乘方向；世界空间和我们构建的 相机空间是左手坐标系
                float3 VScoordY = cross(VScoordZ,VScoordX);  // 左手定理判断叉乘方向;
                float3x3 VS2WSmatrix = {VScoordX,VScoordY,VScoordZ};
                VS2WSmatrix = transpose(VS2WSmatrix); // 转换成列向量
                float3 rayWS = mul(VS2WSmatrix,rayVS); // 计算出世界空间的射线方向
                float3 distanceTotal = RayMarch(camPosWS,rayWS);
                // float3 points = camPosWS + rayWS * distanceTotal;
                // float  dif = GetLight(points);
                // float4 color = dif * _BaseColor;
                return float4(distanceTotal,1.0);
            }
            ENDHLSL
        }
    }
}
