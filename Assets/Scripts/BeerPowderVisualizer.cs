using UnityEngine;

public class BeerPowderVisualizer : MonoBehaviour
{
    public float scatteringCoefficient = 0.05f;
    public float density = 0.1f;
    public float pathLength = 10f;
    public int numberOfSamples = 100;

    private void OnDrawGizmosSelected()
    {
        DrawBeerPowder();
    }

    private void DrawBeerPowder()
    {
        Gizmos.color = Color.blue;

        for (int i = 0; i < numberOfSamples; i++)
        {
            float t = i / (float)(numberOfSamples - 1);
            float x = Mathf.Lerp(0f, pathLength, t);
            float y = 2.0f * Mathf.Exp(-scatteringCoefficient * density * x) * (1.0f - Mathf.Exp(-2.0f * density * x));

            Vector3 point = transform.position + new Vector3(x, y, 0);
            Gizmos.DrawSphere(point, 0.1f);
        }
    }
}
