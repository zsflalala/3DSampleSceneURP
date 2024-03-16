using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[System.Serializable]
[VolumeComponentMenuForRenderPipeline("Custom/SingleAtmosphereVolume", typeof(UniversalRenderPipeline))]
public class SingleAtmosphereVolume : VolumeComponent,IPostProcessComponent
{
    [Header("SingleAtmosphere")]
    public ColorParameter IncomingLight = new ColorParameter(new Color(4f, 4f, 4f, 4f));
    public FloatParameter RayleighScatterCoef = new ClampedFloatParameter(1f, 0f, 10f);
    public FloatParameter RayleighExtinctionCoef = new ClampedFloatParameter(1f, 0f, 10f);
    public FloatParameter MieScatterCoef = new ClampedFloatParameter(1f, 0f, 10f);
    public FloatParameter MieExtinctionCoef = new ClampedFloatParameter(1f, 0f, 10f);
    public FloatParameter MieG = new ClampedFloatParameter(0.76f, 0f, 0.999f);
    public FloatParameter DistanceScale = new ClampedFloatParameter(1f, 0f, 10f);

    public bool IsActive() => true;
    public bool IsTileCompatible() => false;

    public void load(Material material, ref RenderingData renderingData){
        material.SetColor("_IncomingLight", IncomingLight.value);
        material.SetFloat("_RayleighScatterCoef", RayleighScatterCoef.value);
        material.SetFloat("_RayleighExtinctionCoef", RayleighExtinctionCoef.value);
        material.SetFloat("_MieScatterCoef", MieScatterCoef.value);
        material.SetFloat("_MieExtinctionCoef", MieExtinctionCoef.value);
        material.SetFloat("_MieG", MieG.value);
        material.SetFloat("_DistanceScale", DistanceScale.value);
        
    }
}