using UnityEngine;

public static class Noise
{
    public static float[,] GenerateNoiseMap(int mapWidth, int mapHeight, int seed, float scale, int octaves, float persistance, float lacunarity, Vector2 offset)
    {   
        float[,] noiseMap = new float[mapWidth, mapHeight];
        System.Random prng = new System.Random(seed);
        Vector2[] octaveOffsets = new Vector2[octaves];
        for (int i = 0; i < octaves;i++){
            float offsetX = prng.Next(-100000, 100000) + offset.x;
            float offsetY = prng.Next(-100000, 100000) + offset.y;
            octaveOffsets[i] = new Vector2(offsetX, offsetY);
        }

        if (scale <= 0)
        {
            scale = 1e-4f; // 防止scale为0或负数
        }
        
        float maxNoiseHeight = float.MinValue;
        float minNoiseHeight = float.MaxValue;
        float halfWidth = mapWidth / 2f;
        float halfHeight = mapHeight / 2f;

        for(int y = 0; y < mapHeight; y++){
            for (int x = 0; x < mapWidth; x++){
                float amplitude = 1.0f;
                float frequesncy = 1.0f;
                float noiseHeight = 0.0f;

                for (int i = 0;i < octaves; i++){
                    float sampleX = (x - halfWidth) / scale * frequesncy + octaveOffsets[i].x;
                    float sampleY = (y - halfHeight) / scale * frequesncy + octaveOffsets[i].y;
                    float perlinValue = Mathf.PerlinNoise(sampleX, sampleY) * 2 - 1; // -1 -> 1
                    noiseHeight += perlinValue * amplitude;
                    amplitude *= persistance;
                    frequesncy *= lacunarity;
                }
                if (noiseHeight > maxNoiseHeight){
                    maxNoiseHeight = noiseHeight;
                }
                else if(noiseHeight < minNoiseHeight){
                    minNoiseHeight = noiseHeight;
                }
                noiseMap [x,y] = noiseHeight;
            }
        }
        for(int y = 0; y < mapHeight; y++){
            for (int x = 0; x < mapWidth; x++){
                noiseMap [x,y] = Mathf.InverseLerp(minNoiseHeight, maxNoiseHeight, noiseMap [x,y]);
            }
        }
        return noiseMap;
    }
}