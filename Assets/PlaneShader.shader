﻿Shader "Unlit/PlaneShader"
{
	Properties
	{
		_MainTex("Base (RGB) Alpha (A)", 2D) = "white" {}
	}
	SubShader
	{
		Tags{ "Queue" = "Geometry" "RenderType" = "Opaque" }
		Pass
		{
			Tags{ "LightMode" = "ForwardBase" }                      // This Pass tag is important or Unity may not give it the correct light information.
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_fwdbase                       // This line tells Unity to compile this pass for forward base.

			#define MAX_LIGHTS 10
			#include "UnityCG.cginc"
			#include "AutoLight.cginc"

			uniform float _AmbientCoeff;
			uniform float _DiffuseCoeff;
			uniform float _SpecularCoeff;
			uniform float _SpecularPower;
		
			uniform int _NumPointLights;
			uniform float3 _PointLightColors[MAX_LIGHTS];
			uniform float3 _PointLightPositions[MAX_LIGHTS];

			struct vertex_input
			{
				float4 vertex   : POSITION;
				float3 normal   : NORMAL;
				float2 texcoord : TEXCOORD0;
				float4 color    : COLOR;
			};

			struct vertex_output
			{
				float4  pos         : SV_POSITION;
				float2  uv          : TEXCOORD0;
				float4	worldVertex : TEXCOORD1;
				float3  worldNormal	: TEXCOORD2;
				float4  color       : COLOR;
				LIGHTING_COORDS(3,4)    // Macro to send shadow & attenuation to the vertex shader.
			};

			sampler2D _MainTex;
			float4 _MainTex_ST;

			vertex_output vert(vertex_input v)
			{
				vertex_output o;
				float4 worldVertex = mul(_Object2World, v.vertex);
				float3 worldNormal = normalize(mul(transpose((float3x3)_World2Object), v.normal.xyz));

				o.pos = mul(UNITY_MATRIX_MVP, v.vertex);
				o.uv = v.texcoord.xy;
				o.color = v.color;

				o.worldVertex = worldVertex;
				o.worldNormal = worldNormal;

				TRANSFER_VERTEX_TO_FRAGMENT(o);                 // Macro to send shadow & attenuation to the fragment shader.

				return o;
			}

			fixed4 frag(vertex_output i) : COLOR
			{

				fixed atten = LIGHT_ATTENUATION(i); // Macro to get you the combined shadow & attenuation value.

				float3 interpNormal = normalize(i.worldNormal);

				// Calculate ambient RGB intensities
				float Ka = _AmbientCoeff; // (May seem inefficient, but compiler will optimise)
				float3 amb = i.color.rgb * UNITY_LIGHTMODEL_AMBIENT.rgb * Ka;

				// Sum up lighting calculations for each light (only diffuse/specular; ambient does not depend on the individual lights)
				float3 dif_and_spe_sum = float3(0.0, 0.0, 0.0);
				for (int i = 0; i < _NumPointLights; i++)
				{
					// Calculate diffuse RBG reflections, we save the results of L.N because we will use it again
					// (when calculating the reflected ray in our specular component)
					float fAtt = 1;
					float Kd = _DiffuseCoeff;
					float3 L = normalize(_PointLightPositions[i] - i.worldVertex.xyz);
					float LdotN = dot(L, interpNormal);
					float3 dif = fAtt * _PointLightColors[i].rgb * Kd * i.color.rgb * saturate(LdotN);

					// Calculate specular reflections
					float Ks = _SpecularCoeff;
					float specN = _SpecularPower; // Values>>1 give tighter highlights
					float3 V = normalize(_WorldSpaceCameraPos - .worldVertex.xyz);
					// Using Blinn-Phong approximation (note, this is a modification of normal Phong illumination):
					float3 H = normalize(V + L);
					float3 spe = fAtt * _PointLightColors[i].rgb * Ks * pow(saturate(dot(interpNormal, H)), specN);

					dif_and_spe_sum += dif + spe;
				}

				// Combine Phong illumination model components
				float4 returnColor = float4(0.0f, 0.0f, 0.0f, 0.0f);
				returnColor.rgb = amb.rgb + dif_and_spe_sum.rgb;

				fixed4 tex = tex2D(_MainTex, i.uv);

				fixed4 c;
				c.rgb = (UNITY_LIGHTMODEL_AMBIENT.rgb * 2 * tex.rgb * returnColor.rgb);         // Ambient term. Only do this in Forward Base. It only needs calculating once.
				c.rgb += (tex.rgb * returnColor.rgb) * (atten * 2); // Diffuse and specular.
				c.a = tex.a + returnColor.a * atten;
				return c;
			}
				ENDCG
			}

		Pass{
			Tags{ "LightMode" = "ForwardAdd" }                       // Again, this pass tag is important otherwise Unity may not give the correct light information.
			Blend One One                                           // Additively blend this pass with the previous one(s). This pass gets run once per pixel light.
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_fwdadd_fullshadows               // This line tells Unity to compile this pass for forward add, giving attenuation information for the light with full shadow information.

			#include "UnityCG.cginc"
			#include "AutoLight.cginc"

			struct v2f
			{
				float4  pos         : SV_POSITION;
				float2  uv          : TEXCOORD0;
				float3  lightDir    : TEXCOORD2;
				float3 normal		: TEXCOORD1;
				LIGHTING_COORDS(3,4)                            // Macro to send shadow & attenuation to the vertex shader.
			};

			v2f vert(appdata_tan v)
			{
				v2f o;

				o.pos = mul(UNITY_MATRIX_MVP, v.vertex);
				o.uv = v.texcoord.xy;

				o.lightDir = ObjSpaceLightDir(v.vertex);

				o.normal = v.normal;
				TRANSFER_VERTEX_TO_FRAGMENT(o);                 // Macro to send shadow & attenuation to the fragment shader.
				return o;
			}

			sampler2D _MainTex;
			fixed4 _Color;

			fixed4 _LightColor0; // Colour of the light used in this pass.

			fixed4 frag(v2f i) : COLOR
			{
				i.lightDir = normalize(i.lightDir);

				fixed atten = LIGHT_ATTENUATION(i); // Macro to get you the combined shadow & attenuation value.

				fixed4 tex = tex2D(_MainTex, i.uv);

				tex *= _Color;

				fixed3 normal = i.normal;
				fixed diff = saturate(dot(normal, i.lightDir));


				fixed4 c;
				c.rgb = (tex.rgb * _LightColor0.rgb * diff) * (atten * 2); // Diffuse and specular.
				c.a = tex.a;
				return c;
			}
			ENDCG
		}
	}
		FallBack "VertexLit"    // Use VertexLit's shadow caster/receiver passes.
}