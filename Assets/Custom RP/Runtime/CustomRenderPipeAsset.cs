using UnityEngine;
using UnityEngine.Rendering;

[CreateAssetMenu(menuName = "Rendering/Custom Render Pipeline")]
public class CustomRenderPipeAsset : RenderPipelineAsset
{
    protected override RenderPipeline CreatePipeline (){
        return null;
    }
}