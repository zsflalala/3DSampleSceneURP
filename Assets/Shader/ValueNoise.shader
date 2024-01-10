Shader "ShengFu/ValueNoise"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 100

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };
            CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST; 
            CBUFFER_END

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            float N21(float2 p) {
                return frac(sin(p.x*100.+p.y*6574.)*5647.);
            }

            float SmoothNoise(float2 uv) {
                float2 lv = frac(uv);
                float2 id = floor(uv);
                
                lv = lv*lv*(3.-2.*lv);
                
                float bl = N21(id);
                float br = N21(id+float2(1,0));
                float b = lerp(bl, br, lv.x);
                
                float tl = N21(id+float2(0,1));
                float tr = N21(id+float2(1,1));
                float t = lerp(tl, tr, lv.x);
                
                return lerp(b, t, lv.y);
            }

            float SmoothNoise2(float2 uv) {
                float c = SmoothNoise(uv*4.);
                
                // don't make octaves exactly twice as small
                // this way the pattern will look more random and repeat less
                c += SmoothNoise(uv*8.2)*.5;
                c += SmoothNoise(uv*16.7)*.25;
                c += SmoothNoise(uv*32.4)*.125;
                c += SmoothNoise(uv*64.5)*.0625;
                c /= 2.;
                
                return c;
            }

            half4 frag (v2f i) : SV_Target
            {
                float2 uv = i.uv;
                // uv += _Time.y * 0.2;
                float c = SmoothNoise2(uv);
                float3 col = c;
                return float4(col,1.0);
            }
            ENDHLSL
        }
    }
}
