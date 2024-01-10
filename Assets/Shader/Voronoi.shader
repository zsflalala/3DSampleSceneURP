Shader "ShengFu/Voronoi"
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

            float2 hash( float2 p )
            {
                //p = mod(p, 4.0); // tile
                p = float2(dot(p,float2(127.1,311.7)),dot(p,float2(269.5,183.3)));
                return frac(sin(p)*18.5453);
            }

            // return distance, and cell id
            float2 voronoi( in float2 x )
            {
                float2 n = floor( x );
                float2 f = frac( x );

                float3 m = 8.0;
                for( int j=-1; j<=1; j++ ){
                    for( int i=-1; i<=1; i++ )
                    {
                        float2  g = float2( float(i), float(j) );
                        float2  o = hash( n + g );
                    //float2  r = g - f + o;
                        float2  r = g - f + (0.5+0.5*sin(_Time.y+6.2831*o));
                        float d = dot( r, r );
                        if( d<m.x )
                            m = float3( d, o );
                    }
                }
                return float2( sqrt(m.x), m.y+m.z );
            }

            float4 frag (v2f i) : SV_Target
            {
                float2 p = i.uv;//fragCoord.xy / max(iResolution.x,iResolution.y);
                
                // computer voronoi patterm
                float2 c = voronoi( (14.0 + 6.0 * sin(0.2 * _Time.y)) * p);

                // colorize
                float3 col = 0.5 + 0.5 * cos(c.y * 6.2831 + float3(0.0,1.0,2.0) );	
                col *= clamp(1.0 - 0.4 * c.x * c.x, 0.0, 1.0);
                col -= (1.0 - smoothstep( 0.08, 0.09, c.x));
                return float4(col, 1.0 );
            }
            
            ENDHLSL
        }
    }
}
