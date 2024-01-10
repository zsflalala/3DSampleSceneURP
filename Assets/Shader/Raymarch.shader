Shader "Unlit/Raymarch"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            #define MAX_STEPS 100
            #define MAX_DIST 100
            #define SURF_DIST 1e-3

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 ro : TEXCOORD1;
                float3 hitPos : TEXCOORD2;
            };

            float4 _MainTex_ST;
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = v.uv * _MainTex_ST.xy + _MainTex_ST.zw;
                // o.ro = _WorldSpaceCameraPos; // world space
                o.ro = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos.xyz, 1));
                // o.hitPos = o.vertex;         // object space
                // o.hitPos = mul(unity_ObjectToWorld, o.vertex); // world space
                o.hitPos = v.vertex;
                return o;
            }

            float GetDist(float3 p){
                float d = length(p) - .5; // sphere
                // d = length(float2(length(p.xz) - .5, p.y)) - 0.1; // torus
                float3 q = abs(p) - .5; // box
                d = length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0); // box
                q = float3( p.x, max(abs(p.y) - .13 ,0.0), p.z ); // cylinder
                d = length(float2(length(q.xy) - .2 ,q.z)) - .09;
                return d;  
            }

            float Raymarch(float3 ro, float3 rd){
                float dO = 0;
                float dS;
                for(int i = 0;i < MAX_STEPS;i++){
                    float3 p = ro + dO * rd;
                    dS = GetDist(p);
                    dO += dS;
                    if(dS < SURF_DIST || dO > MAX_DIST){
                        break;
                    }
                }
                return dO;
            }

            float3 GetNormal(float3 p){
                float2 e = float2(1e-2, 0);
                float3 n = GetDist(p) - float3(
                        GetDist(p-e.xyy),
                        GetDist(p-e.yxy),
                        GetDist(p-e.yyx)
                    );
                return normalize(n);
            }

            half4 frag (v2f i) : SV_Target
            {
                float2 uv = i.uv - .5;
                float3 ro = i.ro;// float3(0,0,-3);
                float3 rd = normalize(i.hitPos - ro);// normalize(float3(uv.x,uv.y,1));
                float d = Raymarch(ro,rd);
                half4 tex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                half4 col = 0;
                float m = dot(uv,uv);

                if (d >= MAX_DIST){
                    discard;
                }
                else{
                    float3 p = ro + d * rd;
                    float3 n = GetNormal(p);
                    col.rgb = n;
                }

                // if (d < MAX_DIST){
                //     float3 p = ro + d * rd;
                //     float3 n = GetNormal(p);
                //     col.rgb = n;
                // }
                // col = lerp(col,tex,smoothstep(.1, .2, m));
                return col;
            }
            ENDHLSL
        }
    }
}
