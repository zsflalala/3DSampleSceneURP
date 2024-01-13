using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[System.Serializable]
[VolumeComponentMenuForRenderPipeline("Custom/VolumetricCloud", typeof(UniversalRenderPipeline))]
public class VolumetricCloud: VolumeComponent, IPostProcessComponent
{
    [Header("Color")]
    public ColorParameter colorBright = new ColorParameter(new Color(1, 1, 1, 1));
    public ColorParameter colorCentral = new ColorParameter(new Color(1, 1, 1, 1));
    public ColorParameter colorDark = new ColorParameter(new Color(1, 1, 1, 1));
    public FloatParameter colorCentralOffset = new ClampedFloatParameter(0.5f,0.0f,1.0f);

    [Header("Sphere")]
    public Vector4Parameter cloudHeightRange = new Vector4Parameter(new Vector4(1500f, 4000f, 0f, 8000f));
    

    [Header("NoiseTexture")]
    public Texture2DParameter blueNoise = new Texture2DParameter(null);
    public Texture3DParameter shapeNoise = new Texture3DParameter(null);
    public Texture3DParameter detailNoise = new Texture3DParameter(null);
    public Texture2DParameter weatherMap = new Texture2DParameter(null);
    public Texture2DParameter maskNoise = new Texture2DParameter(null);

    [Header("RayMarching")]
    public FloatParameter rayOffsetStrength = new ClampedFloatParameter(10.0f, 0.01f, 30f);
    public IntParameter stepCount = new ClampedIntParameter(32, 1, 128);
    public FloatParameter heightCurveWeight = new ClampedFloatParameter(0.5f, 0.01f, 1.0f);

    [Header("Scattering")]
    [Tooltip("相位函数x:前 y:后 z:调亮系数 w:比例因子")]
    public Vector4Parameter phaseParams = new Vector4Parameter(new Vector4(0.72f, -1.0f, 0.5f, 1.58f));

    [Tooltip("暗部阈值")]
    public FloatParameter darknessThreshold = new ClampedFloatParameter(0.3f, 0.01f, 1.0f);
    
    [Tooltip("消光系数")]
    public FloatParameter absorption = new ClampedFloatParameter(0.02f, 0.01f, 2.0f);
    [Tooltip("反射消光系数")]
    public FloatParameter lightAbsorption = new ClampedFloatParameter(1.0f, 0.01f, 4.0f);

    public Vector4Parameter xy_Speed_zw_Warp = new Vector4Parameter(new Vector4(0.05f, 1f, 1f, 10f));
    public FloatParameter shapeTiling = new FloatParameter(0.01f);
    public FloatParameter detailTiling = new FloatParameter(0.1f);
    public FloatParameter densityMultiplier = new FloatParameter(2.31f);
    public Vector4Parameter shapeNoiseWeights = new Vector4Parameter(new Vector4(-0.17f, 27.17f, -3.65f, -0.08f));
    public FloatParameter densityOffset = new FloatParameter(4.02f);
    public FloatParameter detailWeights = new FloatParameter(-3.76f);
    public FloatParameter detailNoiseWeight = new FloatParameter(0.12f);
    

    public bool IsActive() => true;
    public bool IsTileCompatible() => false;
    public void load(Material material, ref RenderingData data){
        /* 将所有的参数载入目标材质 */
        // 材质
        material.SetColor("_ColorBright", colorBright.value);
        material.SetColor("_ColorCentral", colorCentral.value);
        material.SetColor("_ColorDark", colorDark.value);
        material.SetFloat("_ColorCentralOffset", colorCentralOffset.value);
        if (blueNoise != null){
            material.SetTexture("_BlueNoise", blueNoise.value);
        }
        if (maskNoise != null){
            material.SetTexture("_MaskNoise", maskNoise.value);
        }
        if (weatherMap != null){
            material.SetTexture("_WeatherMap", weatherMap.value);
        }
        if (shapeNoise != null){
            material.SetTexture("_ShapeNoise", shapeNoise.value);
        }
        if (detailNoise != null){
            material.SetTexture("_DetailNoise", detailNoise.value);
        }
        
        // Sphere
        
        material.SetVector("_CloudHeightRange", cloudHeightRange.value);
        

        material.SetFloat("_RayOffsetStrength", rayOffsetStrength.value);
        material.SetInt("_StepCount", stepCount.value);
        material.SetFloat("_HeightCurveWeight", heightCurveWeight.value);



        // 散射函数
        material.SetVector("_PhaseParams",phaseParams.value);
        material.SetFloat("_DarknessThreshold", darknessThreshold.value);
        material.SetFloat("_Absorption", absorption.value);
        material.SetFloat("_LightAbsorption", lightAbsorption.value);

        material.SetVector("_xy_Speed_zw_Warp",xy_Speed_zw_Warp.value);
        material.SetFloat("_ShapeTiling", shapeTiling.value);
        material.SetFloat("_DetailTiling", detailTiling.value);
        material.SetFloat("_DensityMultiplier", densityMultiplier.value);
        material.SetVector("_ShapeNoiseWeights",shapeNoiseWeights.value);
        material.SetFloat("_DensityOffset", densityOffset.value);
        material.SetFloat("_DetailWeights", detailWeights.value);
        material.SetFloat("_DetailNoiseWeight", detailNoiseWeight.value);
    }
}