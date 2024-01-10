using UnityEngine;

public class HenyeyGreensteinVisualizer : MonoBehaviour
{
    public float henyeyGreensteinParameter = 0.5f;
    public int numberOfSamples = 100;

    private void OnDrawGizmosSelected()
    {
        DrawHenyeyGreenstein();
    }

    private void DrawHenyeyGreenstein()
    {
        Gizmos.color = Color.blue;

        for (int i = 0; i < numberOfSamples; i++)
        {
            float theta = Mathf.Lerp(-Mathf.PI, Mathf.PI, i / (float)(numberOfSamples - 1));
            float cosTheta = Mathf.Cos(theta);

            float henyeyGreenstein = (1 - henyeyGreensteinParameter * henyeyGreensteinParameter) /
                                     Mathf.Pow(1 + henyeyGreensteinParameter * henyeyGreensteinParameter - 
                                               2 * henyeyGreensteinParameter * cosTheta, 1.5f);

            float radius = henyeyGreenstein;
            float x = radius * Mathf.Cos(theta);
            float z = radius * Mathf.Sin(theta);

            Vector3 point = transform.position + new Vector3(x, z, 0);
            Gizmos.DrawSphere(point, 0.1f);
        }
    }
}
