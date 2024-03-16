using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;


public class SingleAtmosphereRenderFeatrue : ScriptableRendererFeature
{
    
    SingleAtmosphereRenderPass m_ScriptablePass;
    [SerializeField] private RenderPassEvent m_Event = RenderPassEvent.AfterRenderingPostProcessing;
    [SerializeField] private Shader shader = null;
    private Material mat;

    public override void Create()
    {
        m_ScriptablePass = new SingleAtmosphereRenderPass();
        m_ScriptablePass.renderPassEvent = m_Event;
    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if(shader == null) return;
        if (this.mat == null){
            this.mat = CoreUtils.CreateEngineMaterial(shader);
            Debug.Log("Create material done");
        }
        RenderTargetIdentifier currentRT = renderer.cameraColorTarget;
        m_ScriptablePass.Setup(currentRT,mat);
        renderer.EnqueuePass(m_ScriptablePass);
    }
}