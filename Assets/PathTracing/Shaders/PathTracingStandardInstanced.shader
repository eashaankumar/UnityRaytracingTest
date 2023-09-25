Shader "PathTracing/StandardInstanced"
{
    Properties
    {
        _MainTex("Albedo", 2D) = "white" {}

        _EmissionTex("Emission", 2D) = "white" {}

        _SpecularColor("SpecularColor", Color) = (1, 1, 1, 1)

        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5

        [Gamma] _Metallic("Metallic", Range(0.0, 1.0)) = 0.0

        _IOR("Index of Refraction", Range(1.0, 2.8)) = 1.5
    }    
    
    SubShader
    {
        Pass
        {
            Name "PathTracing"
            Tags{ "LightMode" = "RayTracing" }

            HLSLPROGRAM
   
            #include "UnityRaytracingMeshUtils.cginc"
            #include "RayPayload.hlsl"
            #include "Utils.hlsl"
            #include "GlobalResources.hlsl"

            #pragma raytracing test

            #pragma shader_feature_raytracing _EMISSION
            #pragma multi_compile _ INSTANCING_ON

            #if INSTANCING_ON
                // Unity built-in shader property and represents the index of the fist ray tracing Mesh instance in the TLAS.
                uint unity_BaseInstanceID;

                // How many ray tracing instances were added using RayTracingAccelerationStructure.AddInstances is used. Not used here.
                uint unity_InstanceCount;
            #endif

            struct Data
            {
                float3 color;
                float emission;
            };

            StructuredBuffer<Data> g_Data;

            float4 _SpecularColor;

            Texture2D<float4> _MainTex;
            float4 _MainTex_ST;
            SamplerState sampler__MainTex;

            Texture2D<float4> _EmissionTex;
            float4 _EmissionTex_ST;
            SamplerState sampler__EmissionTex;

            float _Smoothness;
            float _Metallic;
            float _IOR;

            struct AttributeData
            {
                float2 barycentrics;
            };

            struct Vertex
            {
                float3 position;
                float3 normal;
                float2 uv;
            };

            Vertex FetchVertex(uint vertexIndex)
            {
                Vertex v;
                v.position = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributePosition);
                v.normal = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributeNormal);
                v.uv = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord0);
                return v;
            }

            Vertex InterpolateVertices(Vertex v0, Vertex v1, Vertex v2, float3 barycentrics)
            {
                Vertex v;
                #define INTERPOLATE_ATTRIBUTE(attr) v.attr = v0.attr * barycentrics.x + v1.attr * barycentrics.y + v2.attr * barycentrics.z
                INTERPOLATE_ATTRIBUTE(position);
                INTERPOLATE_ATTRIBUTE(normal);
                INTERPOLATE_ATTRIBUTE(uv);
                return v;
            }

            [shader("closesthit")]
            void ClosestHitMain(inout RayPayload payload : SV_RayPayload, AttributeData attribs : SV_IntersectionAttributes)
            {
                if (payload.bounceIndexOpaque == g_BounceCountOpaque)
                {
                    payload.bounceIndexOpaque = -1;
                    return;
                }

                uint3 triangleIndices = UnityRayTracingFetchTriangleIndices(PrimitiveIndex());

                Vertex v0, v1, v2;
                v0 = FetchVertex(triangleIndices.x);
                v1 = FetchVertex(triangleIndices.y);
                v2 = FetchVertex(triangleIndices.z);

                float3 barycentricCoords = float3(1.0 - attribs.barycentrics.x - attribs.barycentrics.y, attribs.barycentrics.x, attribs.barycentrics.y);
                Vertex v = InterpolateVertices(v0, v1, v2, barycentricCoords);
            
#if INSTANCING_ON
                uint instanceID = InstanceIndex() - unity_BaseInstanceID;

                Data instanceData = g_Data[instanceID];
#else
                Data instanceData = g_Data[InstanceID()];
#endif

                float3 emission = float3(0, 0, 0);

                emission = instanceData.color.xyz * instanceData.emission * _EmissionTex.SampleLevel(sampler__EmissionTex, _EmissionTex_ST.xy * v.uv + _EmissionTex_ST.zw, 0).xyz;
              
                bool isFrontFace = HitKind() == HIT_KIND_TRIANGLE_FRONT_FACE;

                float3 localNormal = isFrontFace ? v.normal : -v.normal;

                float3 worldNormal = normalize(mul(localNormal, (float3x3)WorldToObject()));

                float fresnelFactor = FresnelReflectAmountOpaque(isFrontFace ? 1 : _IOR, isFrontFace ? _IOR : 1, WorldRayDirection(), worldNormal);

                float specularChance = lerp(_Metallic, 1, fresnelFactor * _Smoothness);

                // Calculate whether we are going to do a diffuse or specular reflection ray 
                float doSpecular = (RandomFloat01(payload.rngState) < specularChance) ? 1 : 0;

                // Get a cosine-weighted distribution by using the formula from https://www.iue.tuwien.ac.at/phd/ertl/node100.html
                float3 diffuseRayDir = normalize(worldNormal + RandomUnitVector(payload.rngState));

                float3 specularRayDir = reflect(WorldRayDirection(), worldNormal);
              
                specularRayDir = normalize(lerp(diffuseRayDir, specularRayDir, _Smoothness));

                float3 reflectedRayDir = lerp(diffuseRayDir, specularRayDir, doSpecular);

                float3 worldPosition = mul(ObjectToWorld(), float4(v.position, 1)).xyz;

                // Bounced ray origin is pushed off of the surface using the face normal (not the interpolated normal).
                float3 e0 = v1.position - v0.position;
                float3 e1 = v2.position - v0.position;

                float3 worldFaceNormal = normalize(mul(cross(e0, e1), (float3x3)WorldToObject()));

                float3 albedo = instanceData.color.xyz * _MainTex.SampleLevel(sampler__MainTex, _MainTex_ST.xy * v.uv + _MainTex_ST.zw, 0).xyz;

                payload.k                   = (doSpecular == 1) ? specularChance : 1 - specularChance;
                payload.albedo              = lerp(albedo, _SpecularColor.xyz, doSpecular);
                payload.emission            = emission;                
                payload.bounceIndexOpaque   = payload.bounceIndexOpaque + 1;
                payload.bounceRayOrigin     = worldPosition + K_RAY_ORIGIN_PUSH_OFF * worldFaceNormal;
                payload.bounceRayDirection  = reflectedRayDir;
            }

            ENDHLSL
        }
    }

    CustomEditor "PathTracingSimpleShaderGUI"
}