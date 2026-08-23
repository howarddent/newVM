// fft_bench.cu
// Unified C2C single-precision FFT benchmark: FFTW (CPU baseline) vs clFFT
// (OpenCL, matching newVMCL.pas's usage pattern) vs cuFFT (CUDA), for
// N = 4096..16384, to inform whether adding a CUDA-backed capability to
// newVMCL is worth it. Compiled once with nvcc so cuFFT, OpenCL/clFFT and
// FFTW all run in the same process under an identical timing harness.
//
// Methodology mirrors newVMCLfft8192bench.lpr (already in the newVM repo):
// for each library, separately measure (a) first plan-creation cost, (b)
// first exec after that plan exists, (c) steady-state repeated execs on a
// REUSED plan (best case if a real implementation cached plans), and (d) a
// naive replan-every-call loop (create+exec+destroy each time) - which is
// exactly what newVMCL.pas's FFT()/IFFT() do today for clFFT, so (d) is the
// direct apples-to-apples number against the existing implementation.
//
// Build: nvcc -O2 -arch=native fft_bench.cu -o fft_bench \
//          -I/usr/local/include -L/usr/local/lib64 \
//          -lcufft -lOpenCL -lclFFT -lfftw3f
// Run:   LD_LIBRARY_PATH=/usr/local/lib64:$LD_LIBRARY_PATH ./fft_bench

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <vector>
#include <chrono>
#include <string>

#include <cuda_runtime.h>
#include <cufft.h>
#include <CL/cl.h>
#include <clFFT.h>
#include <fftw3.h>

static const int Ns[] = {4096, 6144, 8192, 12288, 16384};
static const int NumSizes = sizeof(Ns) / sizeof(Ns[0]);
static const int Repeats = 100;

typedef std::chrono::high_resolution_clock Clock;
static inline double ms_since(const Clock::time_point &t0) {
    return std::chrono::duration<double, std::milli>(Clock::now() - t0).count();
}

struct Stats { double first, avg, mn, mx; };

static Stats summarize(std::vector<double> &v, double first) {
    Stats s; s.first = first;
    double total = 0, mn = 1e18, mx = 0;
    for (double x : v) { total += x; if (x < mn) mn = x; if (x > mx) mx = x; }
    s.avg = total / v.size(); s.mn = mn; s.mx = mx;
    return s;
}

static void printRow(const char *label, int N, const Stats &s) {
    printf("%-28s N=%-6d first=%9.4f ms   avg=%9.4f ms   min=%9.4f ms   max=%9.4f ms\n",
           label, N, s.first, s.avg, s.mn, s.mx);
}

// ---------------------------------------------------------------------
// FFTW host baseline (CPU, single precision, single-threaded) - same
// FFTW_ESTIMATE|FFTW_PRESERVE_INPUT flags and same "replan every call"
// pattern newVMComplexSingle.pas's FFT()/IFFT() actually use.
// ---------------------------------------------------------------------
static void runFFTW(int N, std::vector<float> &hostIn, double &residual) {
    fftwf_complex *in  = (fftwf_complex*)fftwf_malloc(sizeof(fftwf_complex) * N);
    fftwf_complex *out = (fftwf_complex*)fftwf_malloc(sizeof(fftwf_complex) * N);
    fftwf_complex *back = (fftwf_complex*)fftwf_malloc(sizeof(fftwf_complex) * N);
    for (int i = 0; i < N; i++) { in[i][0] = hostIn[2*i]; in[i][1] = hostIn[2*i+1]; }

    // replan-every-call (matches newVM's actual usage): forward
    std::vector<double> repl;
    double first;
    {
        auto t0 = Clock::now();
        fftwf_plan p = fftwf_plan_dft_1d(N, in, out, FFTW_FORWARD, FFTW_ESTIMATE | FFTW_PRESERVE_INPUT);
        fftwf_execute(p);
        fftwf_destroy_plan(p);
        first = ms_since(t0);
    }
    for (int i = 0; i < Repeats; i++) {
        auto t0 = Clock::now();
        fftwf_plan p = fftwf_plan_dft_1d(N, in, out, FFTW_FORWARD, FFTW_ESTIMATE | FFTW_PRESERVE_INPUT);
        fftwf_execute(p);
        fftwf_destroy_plan(p);
        repl.push_back(ms_since(t0));
    }
    Stats sReplan = summarize(repl, first);
    printRow("FFTW host (replan/call)", N, sReplan);

    // steady-state: plan created once, executed 100x (best case)
    fftwf_plan pPersist = fftwf_plan_dft_1d(N, in, out, FFTW_FORWARD, FFTW_ESTIMATE | FFTW_PRESERVE_INPUT);
    std::vector<double> steady;
    auto t0f = Clock::now(); fftwf_execute(pPersist); double firstExec = ms_since(t0f);
    for (int i = 0; i < Repeats; i++) {
        auto t0 = Clock::now();
        fftwf_execute(pPersist);
        steady.push_back(ms_since(t0));
    }
    Stats sSteady = summarize(steady, firstExec);
    printRow("FFTW host (plan reused)", N, sSteady);
    fftwf_destroy_plan(pPersist);

    // round-trip correctness (forward then inverse, normalize by N)
    fftwf_plan pinv = fftwf_plan_dft_1d(N, out, back, FFTW_BACKWARD, FFTW_ESTIMATE | FFTW_PRESERVE_INPUT);
    fftwf_execute(pinv);
    fftwf_destroy_plan(pinv);
    double sumsq = 0;
    for (int i = 0; i < N; i++) {
        double dre = back[i][0]/N - hostIn[2*i];
        double dim = back[i][1]/N - hostIn[2*i+1];
        sumsq += dre*dre + dim*dim;
    }
    residual = sqrt(sumsq);

    fftwf_free(in); fftwf_free(out); fftwf_free(back);
}

// ---------------------------------------------------------------------
// clFFT (OpenCL) - explicitly selects the NVIDIA CUDA OpenCL platform,
// same fix newVMCLperformance.rtf documents was needed on this machine
// (the first platform clGetPlatformIDs reports is the integrated Intel
// GPU, not the discrete RTX 5070).
// ---------------------------------------------------------------------
static cl_context g_clctx;
static cl_command_queue g_clqueue;
static cl_device_id g_cldevice;

static bool initOpenCL() {
    cl_uint numPlatforms;
    clGetPlatformIDs(0, nullptr, &numPlatforms);
    std::vector<cl_platform_id> platforms(numPlatforms);
    clGetPlatformIDs(numPlatforms, platforms.data(), nullptr);

    cl_platform_id chosen = nullptr;
    for (auto p : platforms) {
        char name[256] = {0};
        clGetPlatformInfo(p, CL_PLATFORM_NAME, sizeof(name), name, nullptr);
        if (strstr(name, "NVIDIA") != nullptr) { chosen = p; break; }
    }
    if (!chosen) { fprintf(stderr, "No NVIDIA OpenCL platform found\n"); return false; }

    cl_uint numDevices;
    clGetDeviceIDs(chosen, CL_DEVICE_TYPE_GPU, 0, nullptr, &numDevices);
    std::vector<cl_device_id> devices(numDevices);
    clGetDeviceIDs(chosen, CL_DEVICE_TYPE_GPU, numDevices, devices.data(), nullptr);
    g_cldevice = devices[0];

    char devname[256] = {0};
    clGetDeviceInfo(g_cldevice, CL_DEVICE_NAME, sizeof(devname), devname, nullptr);
    printf("OpenCL device: %s\n", devname);

    cl_int err;
    g_clctx = clCreateContext(nullptr, 1, &g_cldevice, nullptr, nullptr, &err);
    if (err != CL_SUCCESS) { fprintf(stderr, "clCreateContext failed: %d\n", err); return false; }
    g_clqueue = clCreateCommandQueue(g_clctx, g_cldevice, 0, &err);
    if (err != CL_SUCCESS) { fprintf(stderr, "clCreateCommandQueue failed: %d\n", err); return false; }

    clfftSetupData setupData;
    clfftInitSetupData(&setupData);
    clfftSetup(&setupData);
    return true;
}

static void runCLFFT(int N, std::vector<float> &hostIn, double &residual) {
    cl_int err;
    cl_mem buf = clCreateBuffer(g_clctx, CL_MEM_READ_WRITE, sizeof(float) * 2 * N, nullptr, &err);
    clEnqueueWriteBuffer(g_clqueue, buf, CL_TRUE, 0, sizeof(float) * 2 * N, hostIn.data(), 0, nullptr, nullptr);

    size_t clLen = N;

    // --- naive replan-every-call (exactly newVMCL.pas's FFT() pattern) ---
    std::vector<double> repl;
    double first;
    {
        auto t0 = Clock::now();
        clfftPlanHandle plan;
        clfftCreateDefaultPlan(&plan, g_clctx, CLFFT_1D, &clLen);
        clfftSetPlanPrecision(plan, CLFFT_SINGLE);
        clfftSetLayout(plan, CLFFT_COMPLEX_INTERLEAVED, CLFFT_COMPLEX_INTERLEAVED);
        clfftSetResultLocation(plan, CLFFT_INPLACE);
        clfftBakePlan(plan, 1, &g_clqueue, nullptr, nullptr);
        clfftEnqueueTransform(plan, CLFFT_FORWARD, 1, &g_clqueue, 0, nullptr, nullptr, &buf, nullptr, nullptr);
        clFinish(g_clqueue);
        clfftDestroyPlan(&plan);
        first = ms_since(t0);
    }
    for (int i = 0; i < Repeats; i++) {
        auto t0 = Clock::now();
        clfftPlanHandle plan;
        clfftCreateDefaultPlan(&plan, g_clctx, CLFFT_1D, &clLen);
        clfftSetPlanPrecision(plan, CLFFT_SINGLE);
        clfftSetLayout(plan, CLFFT_COMPLEX_INTERLEAVED, CLFFT_COMPLEX_INTERLEAVED);
        clfftSetResultLocation(plan, CLFFT_INPLACE);
        clfftBakePlan(plan, 1, &g_clqueue, nullptr, nullptr);
        clfftEnqueueTransform(plan, CLFFT_FORWARD, 1, &g_clqueue, 0, nullptr, nullptr, &buf, nullptr, nullptr);
        clFinish(g_clqueue);
        clfftDestroyPlan(&plan);
        repl.push_back(ms_since(t0));
    }
    printRow("clFFT (replan/call)", N, summarize(repl, first));

    // restore input (in-place transform clobbered buf)
    clEnqueueWriteBuffer(g_clqueue, buf, CL_TRUE, 0, sizeof(float) * 2 * N, hostIn.data(), 0, nullptr, nullptr);

    // --- steady-state: bake once, execute 100x (best case) ---
    clfftPlanHandle plan;
    clfftCreateDefaultPlan(&plan, g_clctx, CLFFT_1D, &clLen);
    clfftSetPlanPrecision(plan, CLFFT_SINGLE);
    clfftSetLayout(plan, CLFFT_COMPLEX_INTERLEAVED, CLFFT_COMPLEX_INTERLEAVED);
    clfftSetResultLocation(plan, CLFFT_INPLACE);
    clfftBakePlan(plan, 1, &g_clqueue, nullptr, nullptr);

    auto t0f = Clock::now();
    clfftEnqueueTransform(plan, CLFFT_FORWARD, 1, &g_clqueue, 0, nullptr, nullptr, &buf, nullptr, nullptr);
    clFinish(g_clqueue);
    double firstExec = ms_since(t0f);

    std::vector<double> steady;
    for (int i = 0; i < Repeats; i++) {
        auto t0 = Clock::now();
        clfftEnqueueTransform(plan, CLFFT_FORWARD, 1, &g_clqueue, 0, nullptr, nullptr, &buf, nullptr, nullptr);
        clFinish(g_clqueue);
        steady.push_back(ms_since(t0));
    }
    printRow("clFFT (plan reused, fwd)", N, summarize(steady, firstExec));

    // inverse, same reused plan, steady-state only
    std::vector<double> steadyInv;
    auto t0fi = Clock::now();
    clfftEnqueueTransform(plan, CLFFT_BACKWARD, 1, &g_clqueue, 0, nullptr, nullptr, &buf, nullptr, nullptr);
    clFinish(g_clqueue);
    double firstInv = ms_since(t0fi);
    for (int i = 0; i < Repeats; i++) {
        auto t0 = Clock::now();
        clfftEnqueueTransform(plan, CLFFT_BACKWARD, 1, &g_clqueue, 0, nullptr, nullptr, &buf, nullptr, nullptr);
        clFinish(g_clqueue);
        steadyInv.push_back(ms_since(t0));
    }
    printRow("clFFT (plan reused, inv)", N, summarize(steadyInv, firstInv));
    clfftDestroyPlan(&plan);

    // correctness: forward then inverse. Unlike FFTW/cuFFT, clFFT's
    // CLFFT_BACKWARD direction is auto-scaled by 1/N by default (its
    // default clfftSetPlanScale(CLFFT_BACKWARD) is 1/N, not 1) - so the
    // round trip is already normalized here, no manual /N needed.
    clEnqueueWriteBuffer(g_clqueue, buf, CL_TRUE, 0, sizeof(float) * 2 * N, hostIn.data(), 0, nullptr, nullptr);
    clfftPlanHandle plan2;
    clfftCreateDefaultPlan(&plan2, g_clctx, CLFFT_1D, &clLen);
    clfftSetPlanPrecision(plan2, CLFFT_SINGLE);
    clfftSetLayout(plan2, CLFFT_COMPLEX_INTERLEAVED, CLFFT_COMPLEX_INTERLEAVED);
    clfftSetResultLocation(plan2, CLFFT_INPLACE);
    clfftBakePlan(plan2, 1, &g_clqueue, nullptr, nullptr);
    clfftEnqueueTransform(plan2, CLFFT_FORWARD, 1, &g_clqueue, 0, nullptr, nullptr, &buf, nullptr, nullptr);
    clfftEnqueueTransform(plan2, CLFFT_BACKWARD, 1, &g_clqueue, 0, nullptr, nullptr, &buf, nullptr, nullptr);
    clFinish(g_clqueue);
    clfftDestroyPlan(&plan2);
    std::vector<float> hostOut(2 * N);
    clEnqueueReadBuffer(g_clqueue, buf, CL_TRUE, 0, sizeof(float) * 2 * N, hostOut.data(), 0, nullptr, nullptr);
    double sumsq = 0;
    for (int i = 0; i < N; i++) {
        double dre = hostOut[2*i]   - hostIn[2*i];
        double dim = hostOut[2*i+1] - hostIn[2*i+1];
        sumsq += dre*dre + dim*dim;
    }
    residual = sqrt(sumsq);

    clReleaseMemObject(buf);
}

// ---------------------------------------------------------------------
// cuFFT (CUDA)
// ---------------------------------------------------------------------
static void runCUFFT(int N, std::vector<float> &hostIn, double &residual) {
    cufftComplex *d_data;
    cudaMalloc(&d_data, sizeof(cufftComplex) * N);
    cudaMemcpy(d_data, hostIn.data(), sizeof(cufftComplex) * N, cudaMemcpyHostToDevice);

    // --- naive replan-every-call (apples-to-apples vs clFFT's current pattern) ---
    std::vector<double> repl;
    double first;
    {
        auto t0 = Clock::now();
        cufftHandle plan;
        cufftPlan1d(&plan, N, CUFFT_C2C, 1);
        cufftExecC2C(plan, d_data, d_data, CUFFT_FORWARD);
        cudaDeviceSynchronize();
        cufftDestroy(plan);
        first = ms_since(t0);
    }
    for (int i = 0; i < Repeats; i++) {
        auto t0 = Clock::now();
        cufftHandle plan;
        cufftPlan1d(&plan, N, CUFFT_C2C, 1);
        cufftExecC2C(plan, d_data, d_data, CUFFT_FORWARD);
        cudaDeviceSynchronize();
        cufftDestroy(plan);
        repl.push_back(ms_since(t0));
    }
    printRow("cuFFT (replan/call)", N, summarize(repl, first));

    cudaMemcpy(d_data, hostIn.data(), sizeof(cufftComplex) * N, cudaMemcpyHostToDevice);

    // --- steady-state: plan created once, executed 100x (best case) ---
    cufftHandle plan;
    cufftPlan1d(&plan, N, CUFFT_C2C, 1);

    std::vector<double> steady;
    auto t0f = Clock::now();
    cufftExecC2C(plan, d_data, d_data, CUFFT_FORWARD);
    cudaDeviceSynchronize();
    double firstExec = ms_since(t0f);
    for (int i = 0; i < Repeats; i++) {
        auto t0 = Clock::now();
        cufftExecC2C(plan, d_data, d_data, CUFFT_FORWARD);
        cudaDeviceSynchronize();
        steady.push_back(ms_since(t0));
    }
    printRow("cuFFT (plan reused, fwd)", N, summarize(steady, firstExec));

    std::vector<double> steadyInv;
    auto t0fi = Clock::now();
    cufftExecC2C(plan, d_data, d_data, CUFFT_INVERSE);
    cudaDeviceSynchronize();
    double firstInv = ms_since(t0fi);
    for (int i = 0; i < Repeats; i++) {
        auto t0 = Clock::now();
        cufftExecC2C(plan, d_data, d_data, CUFFT_INVERSE);
        cudaDeviceSynchronize();
        steadyInv.push_back(ms_since(t0));
    }
    printRow("cuFFT (plan reused, inv)", N, summarize(steadyInv, firstInv));
    cufftDestroy(plan);

    // correctness: forward then inverse (cuFFT also unnormalized) then /N
    cudaMemcpy(d_data, hostIn.data(), sizeof(cufftComplex) * N, cudaMemcpyHostToDevice);
    cufftHandle plan2;
    cufftPlan1d(&plan2, N, CUFFT_C2C, 1);
    cufftExecC2C(plan2, d_data, d_data, CUFFT_FORWARD);
    cufftExecC2C(plan2, d_data, d_data, CUFFT_INVERSE);
    cudaDeviceSynchronize();
    cufftDestroy(plan2);
    std::vector<float> hostOut(2 * N);
    cudaMemcpy(hostOut.data(), d_data, sizeof(cufftComplex) * N, cudaMemcpyDeviceToHost);
    double sumsq = 0;
    for (int i = 0; i < N; i++) {
        double dre = hostOut[2*i]/N   - hostIn[2*i];
        double dim = hostOut[2*i+1]/N - hostIn[2*i+1];
        sumsq += dre*dre + dim*dim;
    }
    residual = sqrt(sumsq);

    cudaFree(d_data);
}

int main() {
    srand(12345);
    printf("Unified FFT benchmark: FFTW (host) vs clFFT (OpenCL) vs cuFFT (CUDA)\n");
    printf("Complex-to-complex, single precision, N=4096..16384, %d repeats\n", Repeats);
    printf("======================================================================\n\n");

    if (!initOpenCL()) {
        fprintf(stderr, "OpenCL init failed - aborting\n");
        return 1;
    }
    int cudaDevCount = 0;
    cudaGetDeviceCount(&cudaDevCount);
    if (cudaDevCount == 0) { fprintf(stderr, "No CUDA device found\n"); return 1; }
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    printf("CUDA device: %s (compute %d.%d)\n\n", prop.name, prop.major, prop.minor);

    for (int s = 0; s < NumSizes; s++) {
        int N = Ns[s];
        std::vector<float> hostIn(2 * N);
        for (int i = 0; i < 2 * N; i++) hostIn[i] = (float)rand() / RAND_MAX * 2.0f - 1.0f;

        printf("---- N = %d ----\n", N);
        double residFFTW = 0, residCL = 0, residCU = 0;
        runFFTW(N, hostIn, residFFTW);
        runCLFFT(N, hostIn, residCL);
        runCUFFT(N, hostIn, residCU);
        printf("Round-trip residuals: FFTW=%.3e  clFFT=%.3e  cuFFT=%.3e\n\n", residFFTW, residCL, residCU);
    }

    clfftTeardown();
    return 0;
}
