#pragma once

#include <spdlog/spdlog.h>

#define gpuErrchk(ans)                                                         \
    {                                                                          \
        gpuAssert((ans), __FILE__, __LINE__);                                  \
    }

namespace scalable_ccd::cuda {

inline void
gpuAssert(cudaError_t code, const char* file, int line, bool abort = true)
{
    if (code != cudaSuccess) {
        spdlog::error(
            "GPUassert: {} {} {:d}", cudaGetErrorString(code), file, line);
        if (abort)
            exit(code);
    }
}
} // namespace scalable_ccd::cuda