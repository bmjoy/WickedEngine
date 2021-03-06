#pragma once
#include "wiGraphicsDevice.h"
#include "wiHashString.h"

#include <string>

namespace wiProfiler
{
	typedef size_t range_id;

	// Begin collecting profiling data for the current frame
	void BeginFrame();

	// Finalize collecting profiling data for the current frame
	void EndFrame(wiGraphics::CommandList cmd);

	// Start a CPU profiling range
	range_id BeginRangeCPU(const wiHashString& name);

	// Start a GPU profiling range
	range_id BeginRangeGPU(const wiHashString& name, wiGraphics::CommandList cmd);

	// End a profiling range
	void EndRange(range_id id);

	// Renders a basic text of the Profiling results to the (x,y) screen coordinate
	void DrawData(int x, int y, wiGraphics::CommandList cmd);

	// Enable/disable profiling
	void SetEnabled(bool value);

	bool IsEnabled();
};

