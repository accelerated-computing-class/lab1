// Optional arguments:
//  -r <img_size>
//  -b <max iterations>
//  -i <implementation: {"scalar", "vector"}>

#include <cstdint>
#include <cuda_runtime.h>

/// <--- your code here --->

__global__ void mandelbrot_gpu_scalar(
    uint32_t img_size,
    uint32_t max_iters,
    uint32_t *out /* pointer to GPU memory */
) {
    /* your (GPU) code here... */
    mandelbrot_gpu_scalar<<<1, 1>>>(img_size, max_iters,out);
    for (uint64_t i = 0; i < img_size; ++i) {
        for (uint64_t j = 0; j < img_size; ++j) {
            // Get the plane coordinate X for the image pixel.
            float cx = (float(j) / float(img_size)) * 2.5f - 2.0f;
            float cy = (float(i) / float(img_size)) * 2.5f - 1.25f;

            // Innermost loop: start the recursion from z = 0.
            float x2 = 0.0f;
            float y2 = 0.0f;
            float w = 0.0f;
            uint32_t iters = 0;
            while (x2 + y2 <= 4.0f && iters < max_iters) {
                float x = x2 - y2 + cx;
                float y = w - x2 - y2 + cy;
                x2 = x * x;
                y2 = y * y;
                float z = x + y;
                w = z * z;
                ++iters;
            }

            // Write result.
            out[i * img_size + j] = iters;
        }
    }
}

void launch_mandelbrot_gpu_scalar(
    uint32_t img_size,
    uint32_t max_iters,
    uint32_t *out /* pointer to GPU memory */
) {
    /* your (CPU) code here... */
}

__global__ void mandelbrot_gpu_vector(
    uint32_t img_size,
    uint32_t max_iters,
    uint32_t *out /* pointer to GPU memory */
) {
    /* your (GPU) code here... */
}

void launch_mandelbrot_gpu_vector(
    uint32_t img_size,
    uint32_t max_iters,
    uint32_t *out /* pointer to GPU memory */
) {
    /* your (CPU) code here... */
}

/// <--- /your code here --->

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <vector>

// Useful functions and structures.
enum MandelbrotImpl { SCALAR, VECTOR, ALL };

// Command-line arguments parser.
int ParseArgsAndMakeSpec(
    int argc,
    char *argv[],
    uint32_t *img_size,
    uint32_t *max_iters,
    MandelbrotImpl *impl) {
    char *implementation_str = nullptr;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-r") == 0) {
            if (i + 1 < argc) {
                *img_size = atoi(argv[++i]);
                if (*img_size % 32 != 0) {
                    std::cerr << "Error: Image width must be a multiple of 32"
                              << std::endl;
                    return 1;
                }
            } else {
                std::cerr << "Error: No value specified for -r" << std::endl;
                return 1;
            }
        } else if (strcmp(argv[i], "-b") == 0) {
            if (i + 1 < argc) {
                *max_iters = atoi(argv[++i]);
            } else {
                std::cerr << "Error: No value specified for -b" << std::endl;
                return 1;
            }
        } else if (strcmp(argv[i], "-i") == 0) {
            if (i + 1 < argc) {
                implementation_str = argv[++i];
                if (strcmp(implementation_str, "scalar") == 0) {
                    *impl = SCALAR;
                } else if (strcmp(implementation_str, "vector") == 0) {
                    *impl = VECTOR;
                } else {
                    std::cerr << "Error: unknown implementation" << std::endl;
                    return 1;
                }
            } else {
                std::cerr << "Error: No value specified for -i" << std::endl;
                return 1;
            }
        } else {
            std::cerr << "Unknown flag: " << argv[i] << std::endl;
            return 1;
        }
    }
    std::cout << "Testing with image size " << *img_size << "x" << *img_size << " and "
              << *max_iters << " max iterations." << std::endl;

    return 0;
}

// Output image writers: BMP file header structure
#pragma pack(push, 1)
struct BMPHeader {
    uint16_t fileType{0x4D42};   // File type, always "BM"
    uint32_t fileSize{0};        // Size of the file in bytes
    uint16_t reserved1{0};       // Always 0
    uint16_t reserved2{0};       // Always 0
    uint32_t dataOffset{54};     // Start position of pixel data
    uint32_t headerSize{40};     // Size of this header (40 bytes)
    int32_t width{0};            // Image width in pixels
    int32_t height{0};           // Image height in pixels
    uint16_t planes{1};          // Number of color planes
    uint16_t bitsPerPixel{24};   // Bits per pixel (24 for RGB)
    uint32_t compression{0};     // Compression method (0 for uncompressed)
    uint32_t imageSize{0};       // Size of raw bitmap data
    int32_t xPixelsPerMeter{0};  // Horizontal resolution
    int32_t yPixelsPerMeter{0};  // Vertical resolution
    uint32_t colorsUsed{0};      // Number of colors in the color palette
    uint32_t importantColors{0}; // Number of important colors
};
#pragma pack(pop)

void writeBMP(const char *fname, uint32_t img_size, const std::vector<uint8_t> &pixels) {
    uint32_t width = img_size;
    uint32_t height = img_size;

    BMPHeader header;
    header.width = width;
    header.height = height;
    header.imageSize = width * height * 3;
    header.fileSize = header.dataOffset + header.imageSize;

    std::ofstream file(fname, std::ios::binary);
    file.write(reinterpret_cast<const char *>(&header), sizeof(header));
    file.write(reinterpret_cast<const char *>(pixels.data()), pixels.size());
}

std::vector<uint8_t> iters_to_colors(
    uint32_t img_size,
    uint32_t max_iters,
    const std::vector<uint32_t> &iters) {
    uint32_t width = img_size;
    uint32_t height = img_size;
    auto pixel_data = std::vector<uint8_t>(width * height * 3);
    for (uint32_t i = 0; i < height; i++) {
        for (uint32_t j = 0; j < width; j++) {
            uint32_t iter = iters[i * width + j];

            uint8_t r = 0, g = 0, b = 0;
            if (iter < max_iters) {
                auto log_iter = log2f(static_cast<float>(iter));
                auto intensity = static_cast<uint8_t>(
                    log_iter * 222 / log2f(static_cast<float>(max_iters)));
                r = 32;
                g = 32 + intensity;
                b = 32;
            }

            auto index = (i * width + j) * 3;
            pixel_data[index] = b;
            pixel_data[index + 1] = g;
            pixel_data[index + 2] = r;
        }
    }
    return pixel_data;
}

// Benchmarking macros and configuration.
static constexpr size_t kNumOfOuterIterations = 5;
static constexpr size_t kNumOfInnerIterations = 3;
#define BENCHPRESS(func, ...) \
    do { \
        std::cout << "Running " << #func << " ...\n"; \
        std::vector<double> times(kNumOfOuterIterations); \
        for (size_t i = 0; i < kNumOfOuterIterations; ++i) { \
            auto start = std::chrono::high_resolution_clock::now(); \
            for (size_t j = 0; j < kNumOfInnerIterations; ++j) { \
                func(__VA_ARGS__); \
            } \
            CUDA_CHECK(cudaDeviceSynchronize()); \
            auto end = std::chrono::high_resolution_clock::now(); \
            times[i] = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start) \
                           .count() / \
                kNumOfInnerIterations; \
        } \
        std::sort(times.begin(), times.end()); \
        std::cout << "  Runtime: " << times[0] / 1'000'000 << " ms" << std::endl; \
    } while (0)

// AUX CUDA check functions.
void cuda_check(cudaError_t code, const char *file, int line) {
    if (code != cudaSuccess) {
        std::cerr << "CUDA error at " << file << ":" << line << ": "
                  << cudaGetErrorString(code) << std::endl;
        exit(1);
    }
}

#define CUDA_CHECK(x) \
    do { \
        cuda_check((x), __FILE__, __LINE__); \
    } while (0)

double difference(
    uint32_t img_size,
    uint32_t max_iters,
    std::vector<uint32_t> &result,
    std::vector<uint32_t> &ref_result) {
    int64_t diff = 0;
    for (uint32_t i = 0; i < img_size; i++) {
        for (uint32_t j = 0; j < img_size; j++) {
            diff +=
                abs(int(result[i * img_size + j]) - int(ref_result[i * img_size + j]));
        }
    }
    return diff / double(img_size * img_size * max_iters);
}

// CPU Scalar Mandelbrot set generation.
// Based on the "optimized escape time algorithm" in
// https://en.wikipedia.org/wiki/Plotting_algorithms_for_the_Mandelbrot_set
void mandelbrot_cpu_scalar(uint32_t img_size, uint32_t max_iters, uint32_t *out) {
    for (uint64_t i = 0; i < img_size; ++i) {
        for (uint64_t j = 0; j < img_size; ++j) {
            // Get the plane coordinate X for the image pixel.
            float cx = (float(j) / float(img_size)) * 2.5f - 2.0f;
            float cy = (float(i) / float(img_size)) * 2.5f - 1.25f;

            // Innermost loop: start the recursion from z = 0.
            float x2 = 0.0f;
            float y2 = 0.0f;
            float w = 0.0f;
            uint32_t iters = 0;
            while (x2 + y2 <= 4.0f && iters < max_iters) {
                float x = x2 - y2 + cx;
                float y = w - x2 - y2 + cy;
                x2 = x * x;
                y2 = y * y;
                float z = x + y;
                w = z * z;
                ++iters;
            }

            // Write result.
            out[i * img_size + j] = iters;
        }
    }
}

void dump_image(
    const char *fname,
    uint32_t img_size,
    uint32_t max_iters,
    const std::vector<uint32_t> &iters) {
    // Dump result as an image.
    auto pixel_data = iters_to_colors(img_size, max_iters, iters);
    writeBMP(fname, img_size, pixel_data);
}

// Main function.
// Compile with:
//  g++ -march=native -O3 -Wall -Wextra -o mandelbrot mandelbrot_cpu.cc
int main(int argc, char *argv[]) {
    // Get Mandelbrot spec.
    uint32_t img_size = 256;
    uint32_t max_iters = 1000;
    enum MandelbrotImpl impl = ALL;
    if (ParseArgsAndMakeSpec(argc, argv, &img_size, &max_iters, &impl))
        return -1;

    // Allocate memory.
    std::vector<uint32_t> ref_result(img_size * img_size);
    std::vector<uint32_t> result_host(img_size * img_size);

    // Compute the reference solution
    mandelbrot_cpu_scalar(img_size, max_iters, ref_result.data());

    // Allocate CUDA memory.
    uint32_t *result_device;
    CUDA_CHECK(cudaMalloc(&result_device, img_size * img_size * sizeof(uint32_t)));

    // Test the desired kernels.
    if (impl == SCALAR || impl == ALL) {
        CUDA_CHECK(cudaMemset(result_device, 0, img_size * img_size * sizeof(uint32_t)));
        BENCHPRESS(launch_mandelbrot_gpu_scalar, img_size, max_iters, result_device);
        // Copy result back.
        CUDA_CHECK(cudaMemcpy(
            result_host.data(),
            result_device,
            img_size * img_size * sizeof(uint32_t),
            cudaMemcpyDeviceToHost));
        dump_image("out/mandelbrot_gpu_scalar.bmp", img_size, max_iters, result_host);
        // Check for correctness.
        std::cout << "  Correctness: average output difference from reference = "
                  << difference(img_size, max_iters, result_host, ref_result)
                  << std::endl;
    }

    if (impl == VECTOR || impl == ALL) {
        CUDA_CHECK(cudaMemset(result_device, 0, img_size * img_size * sizeof(uint32_t)));
        BENCHPRESS(launch_mandelbrot_gpu_vector, img_size, max_iters, result_device);
        // Copy result back.
        CUDA_CHECK(cudaMemcpy(
            result_host.data(),
            result_device,
            img_size * img_size * sizeof(uint32_t),
            cudaMemcpyDeviceToHost));
        dump_image("out/mandelbrot_gpu_vector.bmp", img_size, max_iters, result_host);
        // Check for correctness.
        std::cout << "  Correctness: average output difference from reference "
                  << difference(img_size, max_iters, result_host, ref_result)
                  << std::endl;
    }

    // Free CUDA memory.
    CUDA_CHECK(cudaFree(result_device));

    return 0;
}
