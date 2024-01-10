using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[System.Serializable]
[VolumeComponentMenuForRenderPipeline("Custom/VolumetricCloud", typeof(UniversalRenderPipeline))]
public class VolumetricCloud: VolumeComponent, IPostProcessComponent
{
    [Header("Color")]
    [Tooltip("ColorBright")]
    public ColorParameter colorBright = new ColorParameter(new Color(1, 1, 1, 1));
    [Tooltip("ColorCentral")]
    public ColorParameter colorCentral = new ColorParameter(new Color(1, 1, 1, 1));
    [Tooltip("ColorDark")]
    public ColorParameter colorDark = new ColorParameter(new Color(1, 1, 1, 1));
    [Tooltip("ColorCentralOffset")]
    public FloatParameter colorCentralOffset = new ClampedFloatParameter(0.5f,0.0f,1.0f);
    [Header("Box")]
    [Tooltip("盒子中心点(默认原点0)")]
    public Vector3Parameter center = new Vector3Parameter(new Vector3(0.0f, 0.0f,0.0f));
    [Tooltip("盒子长宽高")]
    public Vector3Parameter dimensions = new Vector3Parameter(new Vector3(20.0f, 20.0f,10.0f));
    



    [Tooltip("蓝噪声")]
    public Texture2DParameter blueNoise = new Texture2DParameter(null);
    [Tooltip("2D噪声A")]
    public Texture2DParameter noise2DA = new Texture2DParameter(null);
    [Tooltip("mask噪声B")]
    public Texture2DParameter maskNoise = new Texture2DParameter(null);
    [Tooltip("3D噪声A")]
    public Texture3DParameter noise3DA = new Texture3DParameter(null);
    [Tooltip("3D噪声B")]
    public Texture3DParameter noise3DB = new Texture3DParameter(null);
    [Tooltip("天气图")]
    public Texture2DParameter weatherMap = new Texture2DParameter(null);
    [Tooltip("密度-高度曲线A")]
    public Texture2DParameter heightCurveA = new Texture2DParameter(null);
    [Tooltip("密度-高度曲线B")]
    public Texture2DParameter heightCurveB = new Texture2DParameter(null);
    [Tooltip("2D噪声图速度")]
    public FloatParameter noise2DaSpeed = new ClampedFloatParameter(0.0f, 0f, 0.1f);
    [Tooltip("3D噪声图速度")]
    public FloatParameter noise3DaSpeed = new ClampedFloatParameter(0.0f, .0f, 0.1f);
    [Tooltip("2D噪声图权重")]
    public FloatParameter noise2DWeight = new ClampedFloatParameter(0.15f, .0f, 0.8f);


    [Header("RayMarching")]
    public FloatParameter rayOffsetStrength = new ClampedFloatParameter(10.0f, 0.01f, 30f);
    [Tooltip("RayMarching步进次数")]
    public IntParameter stepCount = new ClampedIntParameter(32, 1, 128);
    // [Tooltip("随机数种子")]
    // public FloatParameter randomNumber = new ClampedFloatParameter(0.1f, 0.0f, 1.0f);
    [Tooltip("高度图采样占比")]
    public FloatParameter heightCurveWeight = new ClampedFloatParameter(0.9f, 0.01f, 1.0f);
    [Tooltip("噪声图采样占比")]
    public FloatParameter densityScale3D = new ClampedFloatParameter(1f, 0.01f, 1f);
    [Tooltip("噪声浓度大小")]
    public Vector3Parameter densityNoiseScale = new Vector3Parameter(Vector3.one);
    [Tooltip("浓度偏移")]
    public Vector3Parameter densityNoiseOffset = new Vector3Parameter(Vector3.zero);
    [Header("Scattering")]
    [Tooltip("相位函数x:前 y:后 z:调亮系数 w:比例因子")]
    public Vector4Parameter phaseParams = new Vector4Parameter(new Vector4(0.72f, -1.0f, 0.5f, 1.58f));
    [Tooltip("相位函数混合")]
    public FloatParameter henyeyBlend = new ClampedFloatParameter(0.3f, 0.01f, 1.0f);
    public FloatParameter henyeyG = new ClampedFloatParameter(0.5f, -1.0f, 1.0f);



    [Tooltip("暗部阈值")]
    public FloatParameter darknessThreshold = new ClampedFloatParameter(0.3f, 0.01f, 1.0f);
    
    [Tooltip("密度阈值")]
    public FloatParameter destinyThreshold = new ClampedFloatParameter(0.02f, 0.01f, 1.0f);
    [Tooltip("消光系数")]
    public FloatParameter absorption = new ClampedFloatParameter(0.02f, 0.01f, 2.0f);
    [Tooltip("光采样步数")]
    public IntParameter lightMarchStep = new ClampedIntParameter(8, 1, 32);
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
        if (noise2DA != null){
            material.SetTexture("_Noise2DA", noise2DA.value);
        }
        if (maskNoise != null){
            material.SetTexture("_MaskNoise", maskNoise.value);
        }
        if (noise3DA != null){
            material.SetTexture("_Noise3DA", noise3DA.value);
        }
        if (noise3DB != null){
            material.SetTexture("_Noise3DB", noise3DB.value);
        }
        if (weatherMap != null){
            material.SetTexture("_WeatherMap", weatherMap.value);
        }
        if (heightCurveA != null){
            material.SetTexture("_HeightCurveA", heightCurveA.value);
        }
        if (heightCurveB != null){
            material.SetTexture("_HeightCurveB", heightCurveB.value);
        }
        material.SetFloat("_Noise2DaSpeed", noise2DaSpeed.value);
        material.SetFloat("_Noise3DaSpeed", noise3DaSpeed.value);
        material.SetFloat("_Noise2DWeight", noise2DWeight.value);
        
        // 体积云
        material.SetVector("_Center", center.value);
        material.SetVector("_Dimensions", dimensions.value);
        material.SetFloat("_RayOffsetStrength", rayOffsetStrength.value);
        material.SetInt("_StepCount", stepCount.value);
        material.SetFloat("_RandomNumber", Random.Range(0.0f, 1.0f));
        material.SetFloat("_HeightCurveWeight", heightCurveWeight.value);
        material.SetFloat("_DensityScale3D", densityScale3D.value);
        material.SetVector("_DensityNoiseScale", densityNoiseScale.value);
        material.SetVector("_DensityNoiseOffset", densityNoiseOffset.value);

        // 散射函数
        material.SetVector("_PhaseParams",phaseParams.value);
        material.SetFloat("_HenyeyBlend", henyeyBlend.value);
        material.SetFloat("_HenyeyG", henyeyG.value);
        material.SetFloat("_DarknessThreshold", darknessThreshold.value);
        material.SetFloat("_DensityThreshold", destinyThreshold.value);
        material.SetFloat("_Absorption", absorption.value);
        material.SetFloat("_LightMarchStep", lightMarchStep.value);
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