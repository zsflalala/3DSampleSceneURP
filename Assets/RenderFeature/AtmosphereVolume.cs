using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace XinYi
{
    [System.Serializable]
    [VolumeComponentMenuForRenderPipeline("XinYi/Atmosphere", typeof(UniversalRenderPipeline))]
    public class AtmosphereVolume: VolumeComponent, IPostProcessComponent{

        [Tooltip("基本颜色")]
        public ColorParameter baseColor = new ColorParameter(new Color(1, 1, 1, 1));

        [Header("RayMarching")]
        [Tooltip("步进次数")]
        public IntParameter stepCount = new ClampedIntParameter(32, 1, 128);

        [Header("Bounding Box")]
        [Tooltip("盒子中心点（默认原点0）")]
        public Vector3Parameter center = new Vector3Parameter(new Vector3(0.0f, 0.0f,0.0f));

        [Tooltip("盒子长宽高")]
        public Vector3Parameter dimensions = new Vector3Parameter(new Vector3(10.0f, 10.0f,10.0f));

        [Header("Density Noise")]
        [Tooltip("密度贴图")]
        public Texture3DParameter densityNoise = new Texture3DParameter(null);

        [Tooltip("高度-密度贴图")]
        public Texture2DParameter heightCurve = new Texture2DParameter(null);

        [Tooltip("采样大小")]
        public Vector3Parameter densityNoiseScale = new Vector3Parameter(new Vector3(5, 5,5));

        [Tooltip("采样偏移")]
        public Vector3Parameter densityNoiseOffset = new Vector3Parameter(Vector3.zero);

        [Tooltip("密度阈值")]
        public FloatParameter densityThreshold = new ClampedFloatParameter(0, 0, 1);

        [Tooltip("密度倍数")]
        public FloatParameter densityMultiplier = new ClampedFloatParameter(1, 0, 10);

        [Header("Light")]
        [Tooltip("消光系数")]
        public FloatParameter absorption = new ClampedFloatParameter(1.0f, 0.0f, 10.0f);

        [Tooltip("云层消光度")]
        public FloatParameter lightAbsorption = new ClampedFloatParameter(1.0f, 0.0f, 10.0f);

        [Tooltip("云层消光度")]
        public FloatParameter lightPower = new ClampedFloatParameter(1.0f, 0.0f, 10.0f);

        public bool IsActive() => true;
        public bool IsTileCompatible() => false;
        public void load(Material material, ref RenderingData data){
            /* 将所有的参数载入目标材质 */
            material.SetColor("_BaseColor", baseColor.value);
            material.SetInt("_StepCount", stepCount.value);
            material.SetVector("_Center", center.value);
            material.SetVector("_Dimensions", dimensions.value);
            if(densityNoise != null){
                material.SetTexture("_DensityNoiseTex", densityNoise.value);
            }

            if (heightCurve != null)
            {
                material.SetTexture("_HeightCurve",heightCurve.value);
            }
            material.SetVector("_DensityNoiseScale", densityNoiseScale.value);
            material.SetVector("_DensityNoiseOffset", densityNoiseOffset.value);
            material.SetFloat("_DensityThreshold", densityThreshold.value);
            material.SetFloat("_DensityMultiplier", densityMultiplier.value);
            material.SetFloat("_Absorption", absorption.value);
            material.SetFloat("_LightAbsorption", lightAbsorption.value);
            material.SetFloat("_LightPower", lightPower.value);
        }
    }
}