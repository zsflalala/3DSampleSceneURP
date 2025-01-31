// using UnityEngine;

// public class PerlinNoise : MonoBehaviour
// {
//     public int width = 256;
//     public int height = 256;
//     public float scale = 20.0f;
//     public float offsetX = 100f;
//     public float offsetY = 100f;

//     Color CalculateColor(int x, int y)
//     {
//         float xCoord = (float)x / width * scale + offsetX;
//         float yCoord = (float)y / height * scale + offsetY;

//         float sample = Mathf.PerlinNoise(xCoord, yCoord);
//         return new Color(sample, sample, sample);
//     }
//     Texture2D GenerateTexture()
//     {
//         Texture2D texture = new Texture2D(width, height);
//         for (int x = 0; x < width; x++){
//             for (int y = 0; y < height; y++){
//                 Color color = CalculateColor(x, y);
//                 texture.SetPixel(x, y, color);
//             }
//         }
//         texture.Apply();
//         return texture;
//     }
    
//     // Start is called before the first frame update
//     void Update()
//     {
//         Renderer renderer = GetComponent<Renderer>();
//         renderer.material.mainTexture = GenerateTexture();
//     }
// }
using UnityEngine;

public static class PerlinNoise
{
    static float interpolate(float a0, float a1, float w)
    {
        //线性插值
        //return (a1 - a0) * w + a0;
        
        //hermite插值
        return Mathf.SmoothStep(a0, a1, w);
    }


    static Vector2 randomVector2(Vector2 p)
    {
        float random = Mathf.Sin(666+p.x*5678 + p.y*1234 )*4321;
        return new Vector2(Mathf.Sin(random), Mathf.Cos(random));
    }


    static float dotGridGradient(Vector2 p1, Vector2 p2)
    {
        Vector2 gradient = randomVector2(p1);
        Vector2 offset = p2 - p1;
        return Vector2.Dot(gradient, offset) / 2 + 0.5f;
    }


    public static float perlin(float x, float y)
    {
        //声明二维坐标
        Vector2 pos = new Vector2(x, y);
        //声明该点所处的'格子'的四个顶点坐标
        Vector2 rightUp = new Vector2((int) x + 1, (int) y + 1);
        Vector2 rightDown = new Vector2((int) x + 1, (int) y);
        Vector2 leftUp = new Vector2((int) x, (int) y + 1);
        Vector2 leftDown = new Vector2((int) x, (int) y);

        //计算x上的插值
        float v1 = dotGridGradient(leftDown, pos);
        float v2 = dotGridGradient(rightDown, pos);
        float interpolation1 = interpolate(v1, v2, x - (int) x);

        //计算y上的插值
        float v3 = dotGridGradient(leftUp, pos);
        float v4 = dotGridGradient(rightUp, pos);
        float interpolation2 = interpolate(v3, v4, x - (int) x);

        float value = interpolate(interpolation1, interpolation2, y - (int) y);
        return value;
    }
}
