#include "globals.hlsli"
#include "cullingShaderHF.hlsli"
#include "tiledLightingHF.hlsli"

//RWTEXTURE2D(DebugTexture, float4, UAVSLOT_DEBUGTEXTURE);
//groupshared uint _counter = 0;

STRUCTUREDBUFFER(in_Frustums, Frustum, SBSLOT_TILEFRUSTUMS);


STRUCTUREDBUFFER(Lights, LightArrayType, SBSLOT_LIGHTARRAY);
#define lightCount xDispatchParams_value0


// Global counter for current index into the light index list.
// "o_" prefix indicates light lists for opaque geometry while 
// "t_" prefix indicates light lists for transparent geometry.
globallycoherent RWSTRUCTUREDBUFFER(o_LightIndexCounter, uint, UAVSLOT_LIGHTINDEXCOUNTERHELPER_OPAQUE);
globallycoherent RWSTRUCTUREDBUFFER(t_LightIndexCounter, uint, UAVSLOT_LIGHTINDEXCOUNTERHELPER_TRANSPARENT);

// Light index lists and light grids.
RWSTRUCTUREDBUFFER(o_LightIndexList, uint, UAVSLOT_LIGHTINDEXLIST_OPAQUE);
RWSTRUCTUREDBUFFER(t_LightIndexList, uint, UAVSLOT_LIGHTINDEXLIST_TRANSPARENT);
RWTEXTURE2D(o_LightGrid, uint2, UAVSLOT_LIGHTGRID_OPAQUE);
RWTEXTURE2D(t_LightGrid, uint2, UAVSLOT_LIGHTGRID_TRANSPARENT);

// Group shared variables.
groupshared uint uMinDepth;
groupshared uint uMaxDepth;
groupshared Frustum GroupFrustum;

// Opaque geometry light lists.
groupshared uint o_LightCount;
groupshared uint o_LightIndexStartOffset;
groupshared uint o_LightList[MAX_LIGHTS];

// Transparent geometry light lists.
groupshared uint t_LightCount;
groupshared uint t_LightIndexStartOffset;
groupshared uint t_LightList[MAX_LIGHTS];

// Add the light to the visible light list for opaque geometry.
void o_AppendLight(uint lightIndex)
{
	uint index; // Index into the visible lights array.
	InterlockedAdd(o_LightCount, 1, index);
	if (index < 1024)
	{
		o_LightList[index] = lightIndex;
	}
}

// Add the light to the visible light list for transparent geometry.
void t_AppendLight(uint lightIndex)
{
	uint index; // Index into the visible lights array.
	InterlockedAdd(t_LightCount, 1, index);
	if (index < 1024)
	{
		t_LightList[index] = lightIndex;
	}
}


[numthreads(BLOCK_SIZE, BLOCK_SIZE, 1)]
void main(ComputeShaderInput IN)
{
	if (IN.groupIndex == 0 && IN.groupID.x == 0 && IN.groupID.y == 0)
	{
		// reset the counter helpers -- maybe it should be done elsewhere? (other pass or updatesubresource)
		o_LightIndexCounter[0] = 0;
		t_LightIndexCounter[0] = 0;
	}

	// Calculate min & max depth in threadgroup / tile.
	int2 texCoord = IN.dispatchThreadID.xy;
	float fDepth = texture_depth.Load(int3(texCoord, 0)).r;

	uint uDepth = asuint(fDepth);

	if (IN.groupIndex == 0) // Avoid contention by other threads in the group.
	{
		uMinDepth = 0xffffffff;
		uMaxDepth = 0;
		o_LightCount = 0;
		t_LightCount = 0;

		// Get frustum from frustum buffer:
		GroupFrustum = in_Frustums[IN.groupID.x + (IN.groupID.y * xDispatchParams_numThreads.x)]; // numthreads is from the frustum computation phase, so not actual number of threads here

		//// Calculate frustum in place:
		//{
		//	// View space eye position is always at the origin.
		//	const float3 eyePos = float3(0, 0, 0);

		//	// Compute 4 points on the far clipping plane to use as the 
		//	// frustum vertices.
		//	float4 screenSpace[4];
		//	// Top left point
		//	screenSpace[0] = float4(IN.dispatchThreadID.xy, 1.0f, 1.0f);
		//	// Top right point
		//	screenSpace[1] = float4(float2(IN.dispatchThreadID.x + BLOCK_SIZE, IN.dispatchThreadID.y), 1.0f, 1.0f);
		//	// Bottom left point
		//	screenSpace[2] = float4(float2(IN.dispatchThreadID.x, IN.dispatchThreadID.y + BLOCK_SIZE), 1.0f, 1.0f);
		//	// Bottom right point
		//	screenSpace[3] = float4(float2(IN.dispatchThreadID.x + BLOCK_SIZE, IN.dispatchThreadID.y + BLOCK_SIZE), 1.0f, 1.0f);

		//	float3 viewSpace[4];
		//	// Now convert the screen space points to view space
		//	for (int i = 0; i < 4; i++)
		//	{
		//		viewSpace[i] = ScreenToView(screenSpace[i]).xyz;
		//	}

		//	// Now build the frustum planes from the view space points
		//	Frustum frustum;

		//	// Left plane
		//	frustum.planes[0] = ComputePlane(eyePos, viewSpace[2], viewSpace[0]);
		//	// Right plane
		//	frustum.planes[1] = ComputePlane(eyePos, viewSpace[1], viewSpace[3]);
		//	// Top plane
		//	frustum.planes[2] = ComputePlane(eyePos, viewSpace[0], viewSpace[1]);
		//	// Bottom plane
		//	frustum.planes[3] = ComputePlane(eyePos, viewSpace[3], viewSpace[2]);

		//	GroupFrustum = frustum;
		//}
	}

	GroupMemoryBarrierWithGroupSync();

	InterlockedMin(uMinDepth, uDepth);
	InterlockedMax(uMaxDepth, uDepth);

	GroupMemoryBarrierWithGroupSync();

	float fMinDepth = asfloat(uMinDepth);
	float fMaxDepth = asfloat(uMaxDepth);

	//fMinDepth = g_xCamera_ZFarP;
	//fMaxDepth = g_xCamera_ZNearP;

	// Convert depth values to view space.
	float minDepthVS = ScreenToView(float4(0, 0, fMinDepth, 1)).z;
	float maxDepthVS = ScreenToView(float4(0, 0, fMaxDepth, 1)).z;
	float nearClipVS = ScreenToView(float4(0, 0, 0, 1)).z;

	// Clipping plane for minimum depth value 
	// (used for testing lights within the bounds of opaque geometry).
	Plane minPlane = { float3(0, 0, 1), minDepthVS };

	// Cull lights
	// Each thread in a group will cull 1 light until all lights have been culled.
	for (uint i = IN.groupIndex; i < lightCount; i += BLOCK_SIZE * BLOCK_SIZE)
	{
		//if (Lights[i].Enabled)
		{
			LightArrayType light = Lights[i];

			switch (light.type)
			{
			case 1/*POINT_LIGHT*/:
			{
				Sphere sphere = { light.PositionVS.xyz, light.range };
				if (SphereInsideFrustum(sphere, GroupFrustum, nearClipVS, maxDepthVS))
				{
					//// Add light to light list for transparent geometry.
					t_AppendLight(i); 
					
					//InterlockedAdd(_counter, 1);

					if (!SphereInsidePlane(sphere, minPlane))
					{
						// Add light to light list for opaque geometry.
						o_AppendLight(i);

						//InterlockedAdd(_counter, 1);
					}

				}
			}
			break;
			//case SPOT_LIGHT:
			//{
			//	float coneRadius = tan(radians(light.SpotlightAngle)) * light.distance;
			//	Cone cone = { light.PositionVS.xyz, light.distance, light.DirectionVS.xyz, coneRadius };
			//	if (ConeInsideFrustum(cone, GroupFrustum, nearClipVS, maxDepthVS))
			//	{
			//		// Add light to light list for transparent geometry.
			//		t_AppendLight(i);

			//		if (!ConeInsidePlane(cone, minPlane))
			//		{
			//			// Add light to light list for opaque geometry.
			//			o_AppendLight(i);
			//		}
			//	}
			//}
			//break;
			case 0/*DIRECTIONAL_LIGHT*/:
			{
				// Directional lights always get added to our light list.
				// (Hopefully there are not too many directional lights!)
				t_AppendLight(i);
				o_AppendLight(i);
			}
			break;
			}
		}
	}

	// Wait till all threads in group have caught up.
	GroupMemoryBarrierWithGroupSync();

	// Update global memory with visible light buffer.
	// First update the light grid (only thread 0 in group needs to do this)
	if (IN.groupIndex == 0)
	{
		// Update light grid for opaque geometry.
		InterlockedAdd(o_LightIndexCounter[0], o_LightCount, o_LightIndexStartOffset);
		o_LightGrid[IN.groupID.xy] = uint2(o_LightIndexStartOffset, o_LightCount);

		// Update light grid for transparent geometry.
		InterlockedAdd(t_LightIndexCounter[0], t_LightCount, t_LightIndexStartOffset);
		t_LightGrid[IN.groupID.xy] = uint2(t_LightIndexStartOffset, t_LightCount);
	}

	GroupMemoryBarrierWithGroupSync();

	// Now update the light index list (all threads).
	// For opaque goemetry.
	for (i = IN.groupIndex; i < o_LightCount; i += BLOCK_SIZE * BLOCK_SIZE)
	{
		o_LightIndexList[o_LightIndexStartOffset + i] = o_LightList[i];
	}
	// For transparent geometry.
	for (i = IN.groupIndex; i < t_LightCount; i += BLOCK_SIZE * BLOCK_SIZE)
	{
		t_LightIndexList[t_LightIndexStartOffset + i] = t_LightList[i];
	}


	//DebugTexture[texCoord] = float4((float)_counter / (float)lightCount,0,0,1);
}