Shader "Hidden/RW/RadialBlur"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _BlurWidth ("Blur Width", Range(0,1)) = 0.85
        _Intensity("Intensity", Range(0,1)) = 1
        _Center("Center", Vector) = (0.5, 0.5, 0.0) // a Vector for the screen space coordinates of the sun, the origin point for the radial blur.
    }
    SubShader
    {
        Blend One One

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            // defines the number of samples to take to blur the image. A high number yields better results, but is also less performant. 
            #define NUM_SAMPLES 100 
            float _BlurWidth;
            float _Intensity;
            float4 _Center;

            #include "UnityCG.cginc"

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

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            sampler2D _MainTex;

            

            fixed4 frag (v2f i) : SV_Target
            {
                // 1 Declare color with a default value of black.
                fixed4 color = fixed4(0.0f, 0.0f, 0.0f, 1.0f);

                // 2 Calculate the ray that goes from the center point towards the current pixel UV coordinates.
                float2 ray = i.uv - _Center.xy;

                // 3 Sample the texture along the ray and accumulate the fragment color.
                for (int i = 0; i < NUM_SAMPLES; i++){
                    float scale = 1.0f - _BlurWidth * (float(i) / float(NUM_SAMPLES - 1));
                    color.xyz += tex2D(_MainTex, (ray * scale) + _Center.xy).xyz / float(NUM_SAMPLES);
                }

                // 4 Multiply color by intensity and return the result.
                return color * _Intensity;
            }
            ENDCG
        }
    }
}
