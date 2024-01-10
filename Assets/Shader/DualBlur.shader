Shader "ShengFu/DualBlur"
{
    Properties
    {
        [HideInInspector] _MainTex ("Texture", 2D) = "white" {}
        _Blur ("Blur",float) = 3.0
    }
    SubShader
    {
        Tags 
        { 
            "RenderType"="Opaque" 
            "RenderPipeline"="UniversalRenderPipeline"
            "IgnoreProjector" = "True"
        }

        Cull Off
        ZTest On
        ZWrite On
        
        Pass
        {
            Name "MyForwardPass"
            Tags
            {
                "LightMode"="UniversalForward"
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            
            CBUFFER_START(UnityPerMaterial)
            float  _Blur;
            float4 _MainTex_ST;
            float4 _MainTex_TexelSize;
            CBUFFER_END

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            struct VertexInput
            {
                float4 postionOS : POSITION;
                float2 texcoord : TEXCOORD0;
            };

            struct VertexOutput
            {
                float4 texcoord[4] : TEXCOORD0;
                float4 postionCS : SV_POSITION;
            };

            VertexOutput vert (VertexInput v)
            {
                VertexOutput o = (VertexOutput)0; 
                o.postionCS = TransformObjectToHClip(v.postionOS);
                o.texcoord[2].xy = v.texcoord;
                o.texcoord[0].xy = v.texcoord + float2(1,1) * _MainTex_TexelSize.xy * (1 + _Blur) * 0.5; 
                o.texcoord[0].zw = v.texcoord + float2(-1,1) * _MainTex_TexelSize.xy * (-1 + _Blur) * 0.5; 
                o.texcoord[1].xy = v.texcoord + float2(1,-1) * _MainTex_TexelSize.xy * (1 + _Blur) * 0.5; 
                o.texcoord[1].zw = v.texcoord + float2(-1,-1) * _MainTex_TexelSize.xy * (-1 + _Blur) * 0.5; 
                return o;
            }

            half4 frag (VertexOutput i) : COLOR
            {
                half4 tex = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,i.texcoord[2].xy) * 0.5;
                for (int t = 0;t < 2;t++){
                   tex += SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,i.texcoord[t].xy) * 0.125;
                    tex += SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,i.texcoord[t].zw) * 0.125;
                }
                return tex;
            }
            ENDHLSL
        }
    }
}
