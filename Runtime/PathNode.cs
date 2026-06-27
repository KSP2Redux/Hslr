using System;
using UnityEngine;

namespace Hslr
{
    [Serializable]
    public struct PathNode
    {
        public Vector3 position;
        public uint color;

        public Color32 Color32
        {
            set
            {
                color = ((uint)value.r << 24) + ((uint)value.g << 16) + ((uint)value.b << 8) + value.a;
            }
        }

        public Color Color
        {
            set
            {
                color = ((uint)Mathf.Round(Mathf.Clamp01(value.r) * 255f) << 24)
                    + ((uint)Mathf.Round(Mathf.Clamp01(value.g) * 255f) << 16)
                    + ((uint)Mathf.Round(Mathf.Clamp01(value.b) * 255f) << 8)
                    + ((uint)Mathf.Round(Mathf.Clamp01(value.a) * 255f));
            }
        }
    }
}