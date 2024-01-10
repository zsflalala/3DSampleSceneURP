using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using System.Collections.Generic;
using System.Linq.Expressions;

[System.Serializable]
public class VolumetricLightScatteringSettings
{
    [Header("Properties")]
    [Range(0.1f, 1f)]
    public float resolutionScale = 0.5f; // Configures the size of your off-screen texture.

    [Range(0.0f, 1.0f)]
    public float intensity = 1.0f;      // Manages the brightness of the light rays you’re generating.

    [Range(0.0f, 1.0f)]
    public float blurWidth = 0.85f;    // The radius of the blur you use when you combine the pixel colors.
}

public class VolumetricLightScattering : ScriptableRendererFeature
{
    class LightScatteringPass : ScriptableRenderPass
    {
        private readonly List<ShaderTagId> shaderTagIdList = new List<ShaderTagId>();
        private readonly RenderTargetHandle occluders  = RenderTargetHandle.CameraTarget; // You need a RenderTargetHandle to create a texture.
        private readonly float resolutionScale; // The resolution scale.
        private readonly float intensity;       // The effect intensity.
        private readonly float blurWidth;       // The radial blur width.
        private readonly Material occludersMaterial; // This will hold the material instance.
        private readonly Material radialBlurMaterial;
        private FilteringSettings filteringSettings = new FilteringSettings(RenderQueueRange.opaque); // indicates which render queue range is allowed: opaque, transparent or all. 
        private RenderTargetIdentifier cameraColorTargetIdent;

        public LightScatteringPass(VolumetricLightScatteringSettings setting){
            occluders.Init("_OccludersMap");
            resolutionScale = setting.resolutionScale;
            intensity = setting.intensity;
            blurWidth = setting.blurWidth;
            occludersMaterial = new Material(Shader.Find("Hidden/RW/UnlitColor"));
            radialBlurMaterial = new Material(Shader.Find("Hidden/RW/RadialBlur"));
            shaderTagIdList.Add(new ShaderTagId("UniversalForward"));
            shaderTagIdList.Add(new ShaderTagId("UniversalForwardOnly"));
            shaderTagIdList.Add(new ShaderTagId("LightweightForward"));
            shaderTagIdList.Add(new ShaderTagId("SRPDefaultUnlit"));
        }

        public void SetCameraColorTarget(RenderTargetIdentifier cameraColorTargetIdent){
            this.cameraColorTargetIdent = cameraColorTargetIdent;
        }

        // Before rendering a camera to configure render targets, this is called.
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            // First, you get a copy of the current camera’s RenderTextureDescriptor. This descriptor contains all the information you need to create a new texture.
            RenderTextureDescriptor cameraTextureDescriptor = renderingData.cameraData.cameraTargetDescriptor;
            
            // Then, you disable the depth buffer because you aren’t going to use it.
            cameraTextureDescriptor.depthBufferBits = 0;

            // You scale the texture dimensions by resolutionScale.
            cameraTextureDescriptor.width = Mathf.RoundToInt(cameraTextureDescriptor.width * resolutionScale);           

            // To create a new texture, you issue a GetTemporaryRT() graphics command. The first parameter is the ID of occluders. 
            // The second parameter is the texture configuration you take from the descriptor you created and the third is the texture filtering mode.
            cmd.GetTemporaryRT(occluders.id, cameraTextureDescriptor, FilterMode.Bilinear);

            // Finally, you call ConfigureTarget() with the texture’s RenderTargetIdentifier to finish the configuration.
            ConfigureTarget(occluders.Identifier());
        }

        // Called every frame to run the rendering logic.
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            // You stop the pass rendering if the material is missing.
            if (!occludersMaterial || !radialBlurMaterial){
                return ;
            }

            // As you know by now, you issue graphic commands via command buffers. 
            // CommandBufferPool is just a collection of pre-created command buffers that are ready to use. You can request one using Get().
            CommandBuffer cmd = CommandBufferPool.Get();

            // You wrap the graphic commands inside a ProfilingScope, which ensures that FrameDebugger can profile the code.
            // Drawing the Light Source
            using (new ProfilingScope(cmd, new ProfilingSampler("VolumetricLightScattering"))){
                // TODO : 1
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                Camera camera = renderingData.cameraData.camera;
                context.DrawSkybox(camera);
                // Before you draw anything, you need to set up a few things. DrawingSettings describes how to sort the objects and which shader passes are allowed. 
                // You create this by calling CreateDrawingSettings(). 
                // You supply this method with the shader passes, a reference to RenderingData and the sorting criteria for visible objects.
                DrawingSettings drawingSettings = CreateDrawingSettings(shaderTagIdList, ref renderingData, SortingCriteria.CommonOpaque);
                // You use the material override to replace the objects’ materials with occludersMaterial.
                drawingSettings.overrideMaterial = occludersMaterial;
                // DrawRenderers handles the actual draw call. It needs to know which objects are currently visible, which is what the culling results are for.
                context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings); 
                
                // TODO : 2 
                // 1 You get a reference to the sun from RenderSettings. You need the forward vector of the sun because directional lights don’t have a position in space.
                Vector3 sunDirectionWorldSpace = RenderSettings.sun.transform.forward;
                // 2 Get the camera position.
                Vector3 cameraPositionWorldSpace = camera.transform.position;
                // 3 This gives you a unit vector that goes from the camera towards the sun. You’ll use this for the sun’s position.
                Vector3 sunPositionWorldSpace = cameraPositionWorldSpace + sunDirectionWorldSpace;
                // 4 The shader expects a viewport space position, but you did your calculations in world space. To fix this, you use WorldToViewportPoint() to transform the point-to-camera viewport space.
                Vector3 sunPositionViewportSpace = camera.WorldToViewportPoint(sunPositionWorldSpace);
                // Keep in mind that you only really need the x and y components of sunPositionViewportSpace since it represents a pixel position on the screen.
                radialBlurMaterial.SetVector("_Center",new Vector4(sunPositionViewportSpace.x, sunPositionViewportSpace.y, 0, 0));
                radialBlurMaterial.SetFloat("_Intensity", intensity);
                radialBlurMaterial.SetFloat("_BlurWidth", blurWidth);
                // The context provides Blit, a function that copies a source texture into a destination texture using a shader. It executes your shader with occluders as the source texture, then stores the output in the camera color target. 
                Blit(cmd, occluders.Identifier(), cameraColorTargetIdent, radialBlurMaterial); 

            }

            // Once you add all the commands to CommandBuffer, you schedule it for execution and release it.
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        // After this render pass executes, call this to clean up any allocated resources — usually render targets.
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            cmd.ReleaseTemporaryRT(occluders.id);
        }

        // Configure(): Before you execute the render pass to configure render targets, you can call this function instead, it executes right after OnCameraSetup()
        // OnFinishCameraStackRendering(): This function is called once after rendering the last camera in the camera stack. You can use this to clean up any allocated resources once all cameras in the stack have finished rendering.
    }

    LightScatteringPass m_ScriptablePass;

    public VolumetricLightScatteringSettings settings = new VolumetricLightScatteringSettings();
    public override void Create()
    {
        m_ScriptablePass = new LightScatteringPass(settings);
        m_ScriptablePass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);
        // This will pass the camera color target to the render pass, which Blit() requires.
        m_ScriptablePass.SetCameraColorTarget(renderer.cameraColorTarget);
    }
}


