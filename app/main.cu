
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <assert.h>
#include <ctype.h>
#include <unistd.h>
#include <cuda.h>
#include <cuda_runtime.h>
#include <iostream>

#include <igl/readOBJ.h>
#include <igl/readPLY.h>
#include <igl/edges.h>

#include <gpubf/simulation.cuh>
#include <gpubf/groundtruth.cuh>
#include <gpubf/util.cuh>
#include <gpubf/io.cuh>
#include <gpubf/aabb.cuh>

#include <gputi/root_finder.h>
#include <gputi/book.h>
#include <gputi/io.h>
#include <gputi/timer.cuh>
#include <gputi/timer.hpp>

using namespace ccd;

#define Vec3Conv(v) {v[0], v[1], v[2]}

// #include <gpubf/klee.cuh>

typedef float Scalar;

using namespace std;

__global__ void addData
(
    int2 * overlaps, 
    Aabb * boxes,
    const double* V0,
    const double* V1, 
    int N, 
    float3** queries
)
{
    int tid = threadIdx.x + blockIdx.x * blockDim.x;
    if (tid >= N) return;

    int3 avids = boxes[overlaps[tid].x].vertexIds;
    int3 bvids = boxes[overlaps[tid].y].vertexIds;

    if (is_face(avids) && is_vertex(bvids))
    {
        int3 tmp = avids;
        avids = bvids;
        bvids = tmp;
    }

    if (is_vertex(avids) && is_face(bvids))
    {
        // auto vertex_start = V0.cast<float>().row(avids.x);
        float3 vertex_start = make_float3(V0[3*avids.x],V0[3*avids.x+1], V0[3*avids.x + 2]);
        // // Triangle at t = 0
        auto face_vertex0_start = make_float3(V0[3*bvids.x], V0[3*bvids.x + 1], V0[3*bvids.x + 2]) ;
        auto face_vertex1_start = make_float3(V0[3*bvids.y], V0[3*bvids.y + 1], V0[3*bvids.y + 2]) ;
        auto face_vertex2_start = make_float3(V0[3*bvids.z], V0[3*bvids.z + 1], V0[3*bvids.z + 2]) ;
        // // Point at t=1
        auto vertex_end = make_float3(V1[3*avids.x], V1[3*avids.x + 1], V1[3*avids.x + 2]) ;
        // // Triangle at t = 1
        auto face_vertex0_end = make_float3(V1[3*bvids.x], V1[3*bvids.x + 1], V1[3*bvids.x + 2]) ;
        auto face_vertex1_end = make_float3(V1[3*bvids.y], V1[3*bvids.y + 1], V1[3*bvids.y + 2]) ;
        auto face_vertex2_end = make_float3(V1[3*bvids.z], V1[3*bvids.z + 1], V1[3*bvids.z + 2]) ;

        // array<array<float, 3>, 8> tmp;
        float3 tmp[8];
        tmp[0] = vertex_start;
        tmp[1] = face_vertex0_start;
        tmp[2] = face_vertex1_start;
        tmp[3] = face_vertex2_start;
        tmp[4] = vertex_end;
        tmp[5] = face_vertex0_end;
        tmp[6] = face_vertex1_end;
        tmp[7] = face_vertex2_end;
        queries[tid] = tmp;
    }
    else if (is_edge(avids) && is_edge(bvids))
    {
        //     // Edge 1 at t=0
        auto edge0_vertex0_start = make_float3(V0[3*avids.x], V0[3*avids.x + 1], V0[3*avids.x + 2]) ;
        auto edge0_vertex1_start = make_float3(V0[3*avids.y], V0[3*avids.y + 1], V0[3*avids.y + 2]) ;
        // // Edge 2 at t=0
        auto edge1_vertex0_start = make_float3(V0[3*bvids.x], V0[3*bvids.x + 1], V0[3*bvids.x + 2]) ;
        auto edge1_vertex1_start = make_float3(V0[3*bvids.y], V0[3*bvids.y + 1], V0[3*bvids.y + 2]) ;
        // // Edge 1 at t=1
        auto edge0_vertex0_end = make_float3(V1[3*avids.x], V1[3*avids.x + 1], V1[3*avids.x + 2]) ;
        auto edge0_vertex1_end = make_float3(V1[3*avids.y], V1[3*avids.y + 1], V1[3*avids.y + 2]) ;
        // // Edge 2 at t=1
        auto edge1_vertex0_end = make_float3(V1[3*bvids.x], V1[3*bvids.x + 1], V1[3*bvids.x + 2]) ;
        auto edge1_vertex1_end = make_float3(V1[3*bvids.y], V1[3*bvids.y + 1], V1[3*bvids.y + 2]) ;
        
        // queries.emplace_back(Vec3Conv(edge0_vertex0_start));
        float3 tmp[8];
        tmp[0] = edge0_vertex0_start;
        tmp[1] = edge0_vertex1_start;
        tmp[2] = edge1_vertex0_start;
        tmp[3] = edge1_vertex1_start;
        tmp[4] = edge0_vertex0_end;
        tmp[5] = edge0_vertex1_end;
        tmp[6] = edge1_vertex0_end;
        tmp[7] = edge1_vertex1_end;
        queries[tid] = tmp;
    }
    else assert(0);
}

void addData(
    const Aabb &a, 
    const Aabb &b, 
    const Eigen::MatrixXd& V0,
    const Eigen::MatrixXd& V1,
    vector<array<array<float, 3>, 8>>& queries)
{
    // auto is_vertex = [&](Aabb x){return x.vertexIds.y < 0 ;};
    // auto is_edge = [&](Aabb x){return !is_vertex(x) && x.vertexIds.z < 0 ;};
    // auto is_face = [&](Aabb x){return !is_vertex(x) && !is_edge(x);};

    // auto is_face = [&](Aabb x){return x.vertexIds.z >= 0;};
    // auto is_edge = [&](Aabb x){return x.vertexIds.z < 0 && x.vertexIds.y >= 0 ;};
    // auto is_vertex = [&](Aabb x){return x.vertexIds.z < 0  && x.vertexIds.y < 0;};

    if (is_vertex(a) && is_face(b))
    {
        auto avids = a.vertexIds;
        auto bvids = b.vertexIds;
            // Point at t=0s
        auto vertex_start = V0.cast<float>().row(avids.x);
        // // Triangle at t = 0
        auto face_vertex0_start = V0.cast<float>().row(bvids.x);
        auto face_vertex1_start = V0.cast<float>().row(bvids.y);
        auto face_vertex2_start = V0.cast<float>().row(bvids.z);
        // // Point at t=1
        auto vertex_end = V1.cast<float>().row(avids.x);
        // // Triangle at t = 1
        auto face_vertex0_end = V1.cast<float>().row(bvids.x);
        auto face_vertex1_end = V1.cast<float>().row(bvids.y);
        auto face_vertex2_end = V1.cast<float>().row(bvids.z);

        array<array<float, 3>, 8> tmp;
        tmp[0] = Vec3Conv(vertex_start);
        tmp[1] = Vec3Conv(face_vertex0_start);
        tmp[2] = Vec3Conv(face_vertex1_start);
        tmp[3] = Vec3Conv(face_vertex2_start);
        tmp[4] = Vec3Conv(vertex_end);
        tmp[5] = Vec3Conv(face_vertex0_end);
        tmp[6] = Vec3Conv(face_vertex1_end);
        tmp[7] = Vec3Conv(face_vertex2_end);
        queries.emplace_back(tmp);
    }
    else if (is_face(a) && is_vertex(b))
        return addData(b, a, V0, V1, queries);
    else if (is_edge(a) && is_edge(b))
    {
        auto avids = a.vertexIds;
        auto bvids = b.vertexIds;
        //     // Edge 1 at t=0
        auto edge0_vertex0_start = V0.cast<float>().row(avids.x);
        auto edge0_vertex1_start = V0.cast<float>().row(avids.y);
        // // Edge 2 at t=0
        auto edge1_vertex0_start = V0.cast<float>().row(bvids.x);
        auto edge1_vertex1_start = V0.cast<float>().row(bvids.y);
        // // Edge 1 at t=1
        auto edge0_vertex0_end = V1.cast<float>().row(avids.x);
        auto edge0_vertex1_end = V1.cast<float>().row(avids.y);
        // // Edge 2 at t=1
        auto edge1_vertex0_end = V1.cast<float>().row(bvids.x);
        auto edge1_vertex1_end = V1.cast<float>().row(bvids.y);
        
        // queries.emplace_back(Vec3Conv(edge0_vertex0_start));
        array<array<float, 3>, 8> tmp;
        tmp[0] = Vec3Conv(edge0_vertex0_start);
        tmp[1] = Vec3Conv(edge0_vertex1_start);
        tmp[2] = Vec3Conv(edge1_vertex0_start);
        tmp[3] = Vec3Conv(edge1_vertex1_start);
        tmp[4] = Vec3Conv(edge0_vertex0_end);
        tmp[5] = Vec3Conv(edge0_vertex1_end);
        tmp[6] = Vec3Conv(edge1_vertex0_end);
        tmp[7] = Vec3Conv(edge1_vertex1_end);
        queries.emplace_back(tmp);
    }
    else abort();
}

bool is_file_exist(const char *fileName)
{
    ifstream infile(fileName);
    return infile.good();
}



__global__ void run_parallel_vf_ccd_all(CCDdata *data,CCDConfig *config_in, bool *res, int size, Scalar *tois
)
{
    int tx = threadIdx.x + blockIdx.x * blockDim.x;
    if (tx >= size) return;
    // copy the input queries to __device__
    CCDdata data_in;
    for (int i = 0; i < 3; i++)
    {
        data_in.v0s[i] = data[tx].v0s[i];
        data_in.v1s[i] = data[tx].v1s[i];
        data_in.v2s[i] = data[tx].v2s[i];
        data_in.v3s[i] = data[tx].v3s[i];
        data_in.v0e[i] = data[tx].v0e[i];
        data_in.v1e[i] = data[tx].v1e[i];
        data_in.v2e[i] = data[tx].v2e[i];
        data_in.v3e[i] = data[tx].v3e[i];
    }
    // copy the configurations to the shared memory
    __shared__ CCDConfig config;
    config.err_in[0]=config_in->err_in[0];
    config.err_in[1]=config_in->err_in[1];
    config.err_in[2]=config_in->err_in[2];
    config.co_domain_tolerance=config_in->co_domain_tolerance; // tolerance of the co-domain
    config.max_t=config_in->max_t; // the upper bound of the time interval
    config.max_itr=config_in->max_itr;// the maximal nbr of iterations
    CCDOut out;
    vertexFaceCCD(data_in,config, out);
    res[tx] = out.result;
    tois[tx] = 0;
}
__global__ void run_parallel_ee_ccd_all(CCDdata *data,CCDConfig *config_in, bool *res, int size, Scalar *tois
)
{
    int tx = threadIdx.x + blockIdx.x * blockDim.x;
    if (tx >= size) return;
    // copy the input queries to __device__
    CCDdata data_in;
    for (int i = 0; i < 3; i++)
    {
        data_in.v0s[i] = data[tx].v0s[i];
        data_in.v1s[i] = data[tx].v1s[i];
        data_in.v2s[i] = data[tx].v2s[i];
        data_in.v3s[i] = data[tx].v3s[i];
        data_in.v0e[i] = data[tx].v0e[i];
        data_in.v1e[i] = data[tx].v1e[i];
        data_in.v2e[i] = data[tx].v2e[i];
        data_in.v3e[i] = data[tx].v3e[i];
    }
    // copy the configurations to the shared memory
    __shared__ CCDConfig config;
    config.err_in[0]=config_in->err_in[0];
    config.err_in[1]=config_in->err_in[1];
    config.err_in[2]=config_in->err_in[2];
    config.co_domain_tolerance=config_in->co_domain_tolerance; // tolerance of the co-domain
    config.max_t=config_in->max_t; // the upper bound of the time interval
    config.max_itr=config_in->max_itr;// the maximal nbr of iterations
    CCDOut out;
    edgeEdgeCCD(data_in,config, out);
    res[tx] = out.result;
    tois[tx] = 0;
}

__global__ void run_parallel_ms_vf_ccd_all(CCDdata *data,CCDConfig *config_in, bool *res, int size, Scalar *tois
)
{
    int tx = threadIdx.x + blockIdx.x * blockDim.x;
    if (tx >= size) return;
    // copy the input queries to __device__
    CCDdata data_in;
    for (int i = 0; i < 3; i++)
    {
        data_in.v0s[i] = data[tx].v0s[i];
        data_in.v1s[i] = data[tx].v1s[i];
        data_in.v2s[i] = data[tx].v2s[i];
        data_in.v3s[i] = data[tx].v3s[i];
        data_in.v0e[i] = data[tx].v0e[i];
        data_in.v1e[i] = data[tx].v1e[i];
        data_in.v2e[i] = data[tx].v2e[i];
        data_in.v3e[i] = data[tx].v3e[i];
    }
    data_in.ms=data[tx].ms;
    // copy the configurations to the shared memory
    __shared__ CCDConfig config;
    config.err_in[0]=config_in->err_in[0];
    config.err_in[1]=config_in->err_in[1];
    config.err_in[2]=config_in->err_in[2];
    config.co_domain_tolerance=config_in->co_domain_tolerance; // tolerance of the co-domain
    config.max_t=config_in->max_t; // the upper bound of the time interval
    config.max_itr=config_in->max_itr;// the maximal nbr of iterations
    CCDOut out;
# ifdef NO_CHECK_MS
    vertexFaceCCD(data_in,config, out);
# else
    vertexFaceMinimumSeparationCCD(data_in,config, out);
#endif
    res[tx] = out.result;
    tois[tx] = 0;
}
__global__ void run_parallel_ms_ee_ccd_all(CCDdata *data,CCDConfig *config_in, bool *res, int size, Scalar *tois
)
{
    int tx = threadIdx.x + blockIdx.x * blockDim.x;
    if (tx >= size) return;
    // copy the input queries to __device__
    CCDdata data_in;
    for (int i = 0; i < 3; i++)
    {
        data_in.v0s[i] = data[tx].v0s[i];
        data_in.v1s[i] = data[tx].v1s[i];
        data_in.v2s[i] = data[tx].v2s[i];
        data_in.v3s[i] = data[tx].v3s[i];
        data_in.v0e[i] = data[tx].v0e[i];
        data_in.v1e[i] = data[tx].v1e[i];
        data_in.v2e[i] = data[tx].v2e[i];
        data_in.v3e[i] = data[tx].v3e[i];
    }
    data_in.ms=data[tx].ms;
    // copy the configurations to the shared memory
    __shared__ CCDConfig config;
    config.err_in[0]=config_in->err_in[0];
    config.err_in[1]=config_in->err_in[1];
    config.err_in[2]=config_in->err_in[2];
    config.co_domain_tolerance=config_in->co_domain_tolerance; // tolerance of the co-domain
    config.max_t=config_in->max_t; // the upper bound of the time interval
    config.max_itr=config_in->max_itr;// the maximal nbr of iterations
    CCDOut out;
# ifdef NO_CHECK_MS
    edgeEdgeCCD(data_in,config, out);
# else
   edgeEdgeMinimumSeparationCCD(data_in,config, out);
#endif
    res[tx] = out.result;
    tois[tx] = 0;
}

void all_ccd_run(const std::vector<std::array<std::array<Scalar, 3>, 8>> &V, bool is_edge,
    std::vector<bool> &result_list, double &run_time, std::vector<Scalar> &time_impact, int parallel_nbr)
{
int nbr = V.size();
result_list.resize(nbr);
// host
CCDdata *data_list = new CCDdata[nbr];
for (int i = 0; i < nbr; i++)
{
data_list[i] = array_to_ccd( V[i]);
#ifndef NO_CHECK_MS
data_list[i].ms=MINIMUM_SEPARATION_BENCHMARK;
#endif
}

bool *res = new bool[nbr];
Scalar *tois = new Scalar[nbr];
CCDConfig *config=new CCDConfig[1];
config[0].err_in[0]=-1;// the input error bound calculate from the AABB of the whole mesh
config[0].co_domain_tolerance=1e-6; // tolerance of the co-domain
config[0].max_t=1; // the upper bound of the time interval
config[0].max_itr=1e6;// the maximal nbr of iterations

// device
CCDdata *d_data_list;
bool *d_res;
Scalar *d_tois;
CCDConfig *d_config;

int data_size = sizeof(CCDdata) * nbr;
int result_size = sizeof(bool) * nbr;
int time_size = sizeof(Scalar) * nbr;
// int dbg_size=sizeof(Scalar)*8;

cudaMalloc(&d_data_list, data_size);
cudaMalloc(&d_res, result_size);
cudaMalloc(&d_tois, time_size);
cudaMalloc(&d_config, sizeof(CCDConfig));

cudaMemcpy(d_data_list, data_list, data_size, cudaMemcpyHostToDevice);
cudaMemcpy(d_config, config, sizeof(CCDConfig), cudaMemcpyHostToDevice);

ccd::Timer timer;
cudaProfilerStart();
timer.start();
#ifdef NO_CHECK_MS
if(is_edge){
run_parallel_ee_ccd_all<<<nbr / parallel_nbr + 1, parallel_nbr>>>( 
d_data_list,d_config, d_res, nbr, d_tois);
}
else{
run_parallel_vf_ccd_all<<<nbr / parallel_nbr + 1, parallel_nbr>>>( 
d_data_list,d_config, d_res, nbr, d_tois);
}
#else
if(is_edge){
run_parallel_ms_ee_ccd_all<<<nbr / parallel_nbr + 1, parallel_nbr>>>( 
d_data_list,d_config, d_res, nbr, d_tois);
}
else{
run_parallel_ms_vf_ccd_all<<<nbr / parallel_nbr + 1, parallel_nbr>>>( 
d_data_list,d_config, d_res, nbr, d_tois);
}
#endif

cudaDeviceSynchronize();
double tt = timer.getElapsedTimeInMicroSec();
run_time = tt;
cudaProfilerStop();

cudaMemcpy(res, d_res, result_size, cudaMemcpyDeviceToHost);
cudaMemcpy(tois, d_tois, time_size, cudaMemcpyDeviceToHost);
//cudaMemcpy(dbg, d_dbg, dbg_size, cudaMemcpyDeviceToHost);

cudaFree(d_data_list);
cudaFree(d_res);
cudaFree(d_tois);
cudaFree(d_config);
//cudaFree(d_dbg);

for (int i = 0; i < nbr; i++)
{
result_list[i] = res[i];
}

time_impact.resize(nbr);

for (int i = 0; i < nbr; i++)
{
time_impact[i] = tois[i];
}
// std::cout << "dbg info\n"
//           << dbg[0] << "," << dbg[1] << "," << dbg[2] << "," << dbg[3] << "," << dbg[4] << "," << dbg[5] << "," << dbg[6] << "," << dbg[7] << std::endl;
delete[] res;
delete[] data_list;
delete[] tois;
delete[] config;
//delete[] dbg;
cudaError_t ct = cudaGetLastError();
printf("******************\n%s\n************\n", cudaGetErrorString(ct));

return;
}


int main( int argc, char **argv )
{
    vector<char*> compare;

    char* filet0;
    char* filet1;

    filet0 = argv[1];
    if (is_file_exist(argv[2])) //CCD
        filet1 = argv[2];
    else //static CD
        filet1 = argv[1];
    
    vector<Aabb> boxes;
    Eigen::MatrixXd vertices_t0;
    Eigen::MatrixXd vertices_t1;
    Eigen::MatrixXi faces; 
    Eigen::MatrixXi edges;

    parseMesh(filet0, filet1, vertices_t0, vertices_t1, faces, edges);
    constructBoxes(vertices_t0, vertices_t1, faces, edges, boxes);
    int N = boxes.size();
    int nbox = 0;
    int parallel = 0;
    int devcount = 1;

    // std::copy(from_vector.begin(), from_vector.end(), to_vector.begin());
    
    int o;
    while ((o = getopt (argc, argv, "c:n:b:")) != -1)
    {
        switch (o)
        {
            case 'c':
                optind--;
                for( ;optind < argc && *argv[optind] != '-'; optind++)
                {
                    compare.push_back(argv[optind]);
                    // compare_mathematica(overlaps, argv[optind]); 
                }
                break;
            case 'n':
                N = atoi(optarg);
                break;
            case 'b':
                nbox = atoi(optarg);
                break;
        }
    }

    vector<pair<int,int>> overlaps;
    int2 * d_overlaps;
    int * d_count;
    run_sweep_pieces(boxes.data(), N, nbox, overlaps, d_overlaps, d_count, parallel, devcount);

    // copy overlap count
    int Noverlaps;
    cudaMemcpy(&Noverlaps, d_count, sizeof(int), cudaMemcpyDeviceToHost);

    // Allocate boxes to GPU 
    Aabb * d_boxes;
    cudaMalloc((void**)&d_boxes, sizeof(Aabb)*N);
    cudaMemcpy(d_boxes, boxes.data(), sizeof(Aabb)*N, cudaMemcpyHostToDevice);

    
    float3 ** d_queries;
    cudaMalloc((void**)&d_queries, sizeof(float3)*8*Noverlaps);

    double * d_vertices_t0;
    double * d_vertices_t1;
    cudaMalloc((void**)&d_vertices_t0, sizeof(double)*3*vertices_t0.rows());
    cudaMalloc((void**)&d_vertices_t1, sizeof(double)*3*vertices_t1.rows());
    cudaMemcpy(d_vertices_t0, vertices_t0.data(), sizeof(double)*3*vertices_t0.rows(), cudaMemcpyHostToDevice);
    cudaMemcpy(d_vertices_t1, vertices_t1.data(), sizeof(double)*3*vertices_t1.rows(), cudaMemcpyHostToDevice);
    

    int grid = (N / parallel + 1); 
    
    addData<<<grid, parallel>>>(d_overlaps, d_boxes, d_vertices_t0, d_vertices_t1, Noverlaps, d_queries );

    cudaFree(d_overlaps);
    cudaFree(d_boxes);
    cudaFree(d_vertices_t0);
    cudaFree(d_vertices_t1);

    cudaGetLastError();

    
    vector<array<array<float, 3>, 8>> queries;
    for (int i=0; i < overlaps.size(); i++)
    {
        int aid = overlaps[i].first;
        int bid = overlaps[i].second;

        Aabb a = boxes[aid];
        Aabb b = boxes[bid];  

        addData(a, b, vertices_t0, vertices_t1, queries);
    }
    int size = queries.size();
    cout << "data loaded, size " << queries.size() << endl;
    double tavg = 0;
    int max_query_cp_size = 1e7;
    int start_id = 0;

    
    vector<float> tois;
    vector<bool> result_list;
    result_list.resize(size);
    tois.resize(size);

    while (1)
    {
        vector<bool> tmp_results;
        vector<array<array<Scalar, 3>, 8>> tmp_queries;
        vector<Scalar> tmp_tois;

        int remain = size - start_id;
        double tmp_tall;

        if (remain <= 0)
            break;

        int tmp_nbr = min(remain, max_query_cp_size);
        tmp_results.resize(tmp_nbr);
        tmp_queries.resize(tmp_nbr);
        tmp_tois.resize(tmp_nbr);
        for (int i = 0; i < tmp_nbr; i++)
        {
            tmp_queries[i] = queries[start_id + i];
        }
        bool is_edge_edge = true;
        all_ccd_run(tmp_queries, is_edge_edge, tmp_results, tmp_tall, tmp_tois, parallel);

        tavg += tmp_tall;
        for (int i = 0; i < tmp_nbr; i++)
        {
            result_list[start_id + i] = tmp_results[i];
            tois[start_id + i] = tmp_tois[i];
        }

        start_id += tmp_nbr;
    }
    tavg /= size;
    cout << "avg time " << tavg << endl;
    
    for (auto i : compare)
    {
        compare_mathematica(overlaps, result_list, i);
    }
    cout << endl;

    // Mesh --> Boxes --> Broadphase --> (Boxes[2] ->float/double[8]) --> Narrowphase
    // Go back to old code and make overlaps as pairs
    
}