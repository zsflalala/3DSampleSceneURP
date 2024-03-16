using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class PrefabScipt : MonoBehaviour
{
    [SerializeField]
    Transform pointProfab = default;
    [SerializeField,Range(10,100)]
    int resolution = 10;
    void Awake()
    {
        var position = Vector3.zero;
        var scale = Vector3.one / 5f;
        for (int i = 0; i < 10; i++){
            Transform point = Instantiate(pointProfab);
            position.x = i / 5f;
            position.y = position.x;
            point.localPosition = position;
            point.localScale = scale;
        }
    }
}
