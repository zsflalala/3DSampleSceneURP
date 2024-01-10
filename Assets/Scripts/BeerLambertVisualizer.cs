using UnityEngine;

public class BeerLambertVisualizer : MonoBehaviour
{
    public float absorptionCoefficient = 0.05f;
    public float pathLength = 10f;
    public float density = 0.1f;
    public int numberOfSamples = 100;

    private void OnDrawGizmosSelected()
    {
        DrawBeerLambert();
    }

    private void DrawBeerLambert()
    {
        Gizmos.color = Color.red;

        for (int i = 0; i < numberOfSamples; i++)
        {
            float t = i / (float)(numberOfSamples - 1);
            float x = Mathf.Lerp(0f, pathLength, t);
            float y = Mathf.Exp(-absorptionCoefficient * density * x);

            Vector3 point = transform.position + new Vector3(x, y, 0);
            Gizmos.DrawSphere(point, 0.1f);
        }
    }
}
