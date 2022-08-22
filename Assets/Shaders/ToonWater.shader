Shader "Roystan/Toon/Water"
{
    Properties
    {	
        _DepthGradientShallow("Depth Gradient Shallow", Color) = (0.325, 0.807, 0.971, 0.725)//These three properties will allow us to change the colour of the water based on the water's depth.
        _DepthGradientDeep("Depth Gradient Deep", Color) = (0.086, 0.407, 1, 0.749)
        _DepthMaxDistance("Depth Maximum Distance", Float) = 1

        _SurfaceNoise("Surface Noise", 2D) = "white" {}//Texture property used to make the waves.
        _SurfaceNoiseCutoff("Surface Noise Cutoff", Range(0, 1)) = 0.777//To make the brightness of the waves seem less randomly varied.

        //_FoamDistance("Foam Distance", Float) = 0.4//Controlling from what depth the shoreline is visible.
        _FoamMaxDistance("Foam Maximum Distance", Float) = 0.4//Replaced the property above with these two later on.
        _FoamMinDistance("Foam Minimum Distance", Float) = 0.04

        _SurfaceNoiseScroll("Surface Noise Scroll Amount", Vector) = (0.03, 0.03, 0, 0)//Controllin the movement of the waves.

        _SurfaceDistortion("Surface Distortion", 2D) = "white" {}	
        _SurfaceDistortionAmount("Surface Distortion Amount", Range(0, 1)) = 0.27

        _FoamColor("Foam Color", Color) = (1,1,1,1)//Controlling the colour of the water's foam.

    }
    SubShader
    {
        Tags
        {
	        "Queue" = "Transparent"
        }
        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha//Determines how blending occurs. We are using the "normal blending" algorithm...
            ZWrite Off//Prevents shader from being used by the depth buffer.

			CGPROGRAM

            #define SMOOTHSTEP_AA 0.01//for the smooth step function for smooth transition of water to foam.

            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            
            float4 alphaBlend(float4 top, float4 bottom)
            {
	            float3 color = (top.rgb * top.a) + (bottom.rgb * (1 - top.a));
	            float alpha = top.a + bottom.a * (1 - top.a);

	            return float4(color, alpha);
            }

            struct appdata
            {
                float4 vertex : POSITION;
                float4 uv : TEXCOORD0;//For the waves
                float3 normal : NORMAL;//Viewspace normal of the water's surface.
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float4 screenPosition : TEXCOORD2;
                float2 noiseUV : TEXCOORD0;//For the waves.
                float2 distortUV : TEXCOORD1; //For distortion of the waves 
                float3 viewNormal : NORMAL;
            };

            sampler2D _SurfaceNoise;
            float4 _SurfaceNoise_ST;
            float _SurfaceNoiseCutoff;//Make the waves less randomly brightened.

            float4 _DepthGradientShallow;
            float4 _DepthGradientDeep;

            float _DepthMaxDistance;

            sampler2D _CameraDepthTexture;

            //float _FoamDistance;
            float _FoamMaxDistance;//Replaced the variable above with these two later on.
            float _FoamMinDistance;

            float2 _SurfaceNoiseScroll;

            sampler2D _SurfaceDistortion;
            float4 _SurfaceDistortion_ST;

            float _SurfaceDistortionAmount;

            sampler2D _CameraNormalsTexture;

            float4 _FoamColor;

            v2f vert (appdata v)
            {
                v2f o;

                o.vertex = UnityObjectToClipPos(v.vertex);
                o.screenPosition = ComputeScreenPos(o.vertex);//The position of the current vertex we are rendering. We need this to be able to sample the greyscale texture at the correct place.
                o.noiseUV = TRANSFORM_TEX(v.uv, _SurfaceNoise);//For the waves.
                o.distortUV = TRANSFORM_TEX(v.uv, _SurfaceDistortion);
                o.viewNormal = COMPUTE_VIEW_NORMAL;

                return o;
            }



            float4 frag (v2f i) : SV_Target
            {
                float existingDepth01 = tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPosition)).r;//Sampling depth texture at correct position. This returns of the depth of the surface below the water.
                float existingDepthLinear = LinearEyeDepth(existingDepth01);

                float depthDifference = existingDepthLinear - i.screenPosition.w;//Depth between the water's surface and the surface below the water, this is the actual value the depth texture will consider.
                float waterDepthDifference01 = saturate(depthDifference / _DepthMaxDistance);
                float4 waterColor = lerp(_DepthGradientShallow, _DepthGradientDeep, waterDepthDifference01);//Color is interpolating between the deep and shallow gradients based on the percentage of depth a pixel of water compared to our max depth variable.
               
                float2 distortSample = (tex2D(_SurfaceDistortion, i.distortUV).xy * 2 - 1) * _SurfaceDistortionAmount;
                float2 noiseUV = float2((i.noiseUV.x + _Time.y * _SurfaceNoiseScroll.x) + distortSample.x, (i.noiseUV.y + _Time.y * _SurfaceNoiseScroll.y) + distortSample.y);//Offsetting the UVs for the noise texture at '_SurfaceNoiseScroll' rate.
                float surfaceNoiseSample = tex2D(_SurfaceNoise,  noiseUV).r;

                float3 existingNormal = tex2Dproj(_CameraNormalsTexture, UNITY_PROJ_COORD(i.screenPosition));//Sampling the normals texture to compare the normal of water surface to the normal of the object below water surface.
                float3 normalDot = saturate(dot(existingNormal, i.viewNormal));//Dot product of the the two normals, that of the water surface and that of the object beneath it.
           
                float foamDistance = lerp(_FoamMaxDistance, _FoamMinDistance, normalDot);//foam distance value alternates depending on the dot product of the normal of the water surface and the surface below it on a particular spot.
                float foamDepthDifference01 = saturate(depthDifference / foamDistance);//saturation gives us a value between 0 and 1.
               
                float surfaceNoiseCutoff = foamDepthDifference01 * _SurfaceNoiseCutoff;
                //float surfaceNoise = surfaceNoiseSample > surfaceNoiseCutoff ? 1 : 0;
                float surfaceNoise = smoothstep(surfaceNoiseCutoff - SMOOTHSTEP_AA, surfaceNoiseCutoff + SMOOTHSTEP_AA, surfaceNoiseSample);
                //float4 surfaceNoiseColor = _FoamColor * surfaceNoise;//We can just set the foam colour ourselves manually from the inspector.
                float4 surfaceNoiseColor = _FoamColor;
                surfaceNoiseColor.a *= surfaceNoise;

                return alphaBlend(surfaceNoiseColor, waterColor);
                //return waterColor + surfaceNoiseColor;
                //zreturn waterColor + surfaceNoise;
                //return waterColor + surfaceNoiseSample;
                //return waterColor;
                //return depthDifference;
				//return float4(1, 1, 1, 0.5);
            }
            ENDCG
        }
    }
}