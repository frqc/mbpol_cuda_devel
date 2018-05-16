
/**
* This file describes Neural Network model class and layer class based on CUDNN/CUBLAS/CUDA library
* 
* It is created from NVIDIA's CUDNN example: "mnistCUDNN.cpp" in which the following desclaimed is contained:
*
***********************************************************************
* Copyright 2014 NVIDIA Corporation.  All rights reserved.
*
* Please refer to the NVIDIA end user license agreement (EULA) associated
* with this source code for terms and conditions that govern your use of
* this software. Any use, reproduction, disclosure, or distribution of
* this software and related documentation outside the terms of the EULA
* is strictly prohibited.
***********************************************************************
*
*
* ===========================================================================================================================
*
* Some concept good to know for CUDNN/CUBLAS:
*    - CUDNN/CUBLAS needs a Handle to initialze its context. This Handle will be passed in all calling to its subfunctions.
*         -- This Handle is used to control library's function on host threads, GPUs and CUDA streams.
*         -- Create this Handle at the beginning, and destroy it after finishing application to release resource.
*    - CUDNN initialize a TensorDescriptor (or in simple words, a matrix with unspecific dimensionality and size) 
*      that helps holds data throughout the Neural Network flow
*         -- This TensorDescriptor needs to be created at beginning, specified dimensionality and size before use, 
*            and destroyed after application
*         -- There are some pre-defined type of TensorDescriptors avaiable in CUDNN, but minimum dimensionality is 3.
*            In our test case, we use the simplest 3d Tensor [batch_num(training samples each time, simply = 1 in toy_tester), x(simply = 1), y]
*    - There are pre-defined Tensor operations used for describing Neural Network layer operation algorithm
*         -- E.g., cudnnActivationForward() will take input Tensor and output its activation resutls.
*         -- However, there is no function describing basic Fully Connected layer algorithm, 
*            as this algorithm is only an utilization of function cublasSgemv() from CUBLAS.
*            This is why CUBLAS is needed.
*
* Hope these explanations will help your understanding of CUDNN.
*
* - By Yaoguang Zhai, 2017.07.14
*
*=============================================================================================================================
*.
* This file is for the purpose of using CUDNN library to implement basic NN models.
* It uses the "error_util.h" file coming from the "mnistCUDNN" example composed by nVIDIA.
*
* Currtent implemented contents include:
*    - Layers, its input/output dimension (m,n), the weighted matrix (W[m,n]), a bias vector (b[n])
*              and a kernal dimension (1X1, for convolution layer)
*    - simple fully connecte forward, using cublasSgemv() function
*    - softmax forwards, using cudnnSoftmaxForward()
*    - Activation_TANH forwards, using cudnnActivationForward() with CUDNN_ACTIVATION_TANH
*    - Activation_ReLU forwards, using cudnnActivationForward() with CUDNN_ACTIVATION_RELU
*
* The code currently works with single precision float.
*
* Future implement:
*    - Double, half precision support
*    - Convolution NN support
*
*=======================================================================
*
*Log:
*    - 2017.07.10 by Yaoguang Zhai:     First version 0.1
*    - 2017.07.14 by Yaoguang Zhai:     Ver 0.2
*                                       Change the TensorDescriptor from 4D to 3D.
*                                       Functions that are not used in test case are removed to reduce learning distraction.
*    - 2017.07.25 by Yaoguang Zhai:     Ver 0.3
*                                       Class now accept single/double precision data
*                                       Create a list of layers tracking the initialization of NN model
*                                       Class now accept multiple sample inputs
*                                       
*/

#ifndef _NN_H_
#define _NN_H_


#include <iostream>
#include <sstream>
#include <fstream>
#include <stdlib.h>
#include <string>
#include <algorithm>   
#include <limits>
#include<cuda.h>
#include<cudnn.h>
#include<cublas_v2.h>

#include"error_util.hpp"
#include"whichtype.hpp"
#include "readhdf5.hpp"
#include "Gfunction_v2.cuh"

//hdf5 file things
#define PATHTOMODEL "/model_weights"    // usual path to the group saving all the layers in HDF5 file
#define LAYERNAMES  "layer_names"       // Attribute name saving the list of layer names in HDF5
#define WEIGHTNAMES "weight_names"      // Attribute name saving the list of weight names in HDF5
#define EUNIT (6.0)/(.0433634) //energy conversion factor 


using namespace std;

// Helper function showing the data on Device
template <typename T>
void printDeviceVector(int size, T* vec_d)
{
    T *vec;
    vec = new T[size];
    cudaDeviceSynchronize();
    cudaMemcpy(vec, vec_d, size*sizeof(T), cudaMemcpyDeviceToHost);
    if(TypeIsDouble<T>::value) {
          std::cout.precision(std::numeric_limits<double>::digits10+1);
    } else {
          std::cout.precision(std::numeric_limits<float>::digits10+1);;
    }
    std::cout.setf( std::ios::fixed, std::ios::floatfield );
    for (int i = 0; i < size; i++)
    {
        std::cout << (vec[i]) << " ";
    }
    std::cout << std::endl;
    delete [] vec;
}

//===========================================================================================================
// Type of layers
enum class Type_t {
     UNINITIALIZED  = 0 ,
     DENSE          = 1 ,
     ACTIVIATION    = 2 , 
     MAX_TYPE_VALUE = 3
};


// Type of activiation layer
enum class ActType_t {
     NOACTIVIATION  = 0 ,
     LINEAR         = 1 ,
     TANH           = 2 ,
     MAX_ACTTYPE_VALUE = 3
};



// define layers
template <typename T>
struct Layer_t
{
    string name;
    
    Type_t type ;
                    
    ActType_t acttype;               
    
    int inputs;     // number of input dimension
    int outputs;    // number of output dimension
    T *data_h, *data_d;  // weight matrix in host and device
    T *bias_h, *bias_d;  // bias vector in host and device
    
    Layer_t<T>* prev=nullptr;  // list ptr to previous layer
    Layer_t<T>* next=nullptr;  // list ptr to next layer
    
    
    Layer_t<T>() :  name("Default_Layer"), data_h(NULL), data_d(NULL), bias_h(NULL), bias_d(NULL), 
                inputs(0), outputs(0), type(Type_t::UNINITIALIZED), acttype(ActType_t::NOACTIVIATION) {};
                
    
    
    // construct dense layer via loaded matrix from host
    Layer_t<T>( string _name, int _inputs, int _outputs, 
          T* _data_h, T* _bias_h)
                  : inputs(_inputs), outputs(_outputs), type(Type_t::DENSE), acttype(ActType_t::NOACTIVIATION)
    {     
        name = _name ;
        data_h = new T[inputs*outputs];       
        bias_h = new T[outputs];
        copy(_data_h, (_data_h+inputs*outputs), data_h);
        copy(_bias_h, (_bias_h+       outputs), bias_h);

        readAllocMemcpy( inputs * outputs, 
                        &data_h, &data_d);
        readAllocMemcpy( outputs, &bias_h, &bias_d);
        
        // Some tester, if need to check layer input
        //cout<< "Layer weights initializing: " << endl;
        //printDeviceVector(inputs * outputs, data_d);
        
        //cout<< "Layer bias initializing: " <<endl;
        //printDeviceVector( outputs, bias_d);
    }
    
    // construct an activation layer, by integer or by typename
    Layer_t<T>(string _name, int _acttype)
                  : data_h(NULL), data_d(NULL), bias_h(NULL), bias_d(NULL), 
                inputs(0), outputs(0), type(Type_t::ACTIVIATION)
    {     
          if (_acttype < int(ActType_t::MAX_ACTTYPE_VALUE) ) {
               acttype = static_cast<ActType_t>(_acttype);
          }
          name = _name;
    }    
    
    Layer_t<T>(string _name, ActType_t _acttype)
                  : data_h(NULL), data_d(NULL), bias_h(NULL), bias_d(NULL), 
                inputs(0), outputs(0), type(Type_t::ACTIVIATION)
    {      
          acttype = _acttype;
          
          name = _name;
    }          
    
    
    ~Layer_t<T>()
    { 
        if (data_h != NULL) delete [] data_h;
        if (data_d != NULL) checkCudaErrors( cudaFree(data_d) );
        if (bias_h != NULL) delete [] bias_h;
        if (bias_d != NULL) checkCudaErrors( cudaFree(bias_d) );
    }
    
    
private:

     // Allocate device memory from existing data_h
     void readAllocMemcpy(int size, T** data_h, T** data_d)
     {
         int size_b = size*sizeof(T);
         checkCudaErrors( cudaMalloc(data_d, size_b) );
         checkCudaErrors( cudaMemcpy(*data_d, *data_h,
                                     size_b,
                                     cudaMemcpyHostToDevice) );
     }    
     
};


// ===========================================================================================================================================
//
// Function to perform forward action on fully connected layer, according to different type of data
// Must be used after CUBLAS handle has been initialized and matrix saved to device.
//
// Return matrix(C) = alpha * matrx(A[_out,_in]) dot matrix(X[_in,N]) + beta * matrix(bias[_out,N])
// _in/out     : layer's in/out dimension    
// N           : number of samples
// alpha/beta  : scalars
//
//
// Tricky Here!!!! Must use [col row] as input towards cublasSgemm()/cublasDgemm instead of [row col], 
// since CUBLAS uses a "column-major" matrix instead of common "row-major" matrix.
// e.g., for a matrix A =  [a11 a12 a13]
//                         [a21 a22 a23]
// in row-major, sequence of cell in memory is [a11 a12 a13 a21 a22 a23]  <- in our case the data are saved in this way
// in column-major, sequence is [a11 a21 a12 a22 a13 a23]
// Therefore, we must claim to CUBLAS that the saved data ([m,n]) has [n] "rows" and [m] "cols" 
// And DO NOT transpose them, as the matrices have already been regarded as "transposed" matrices in the eye of CUBLAS.


template <typename T>
struct gemm{
     gemm(          cublasHandle_t cublasHandle, int N, int _input_vector_length, int _output_vector_length, int _vector_pitch, 
                    void *_weight, void *_inputs, void *_bias,
                    double alpha=1.0, double beta=1.0){
                    cout << " Don't know what to do with this type of data " << endl;
     };
};

template <>
struct gemm<double>{
     gemm<double> (cublasHandle_t cublasHandle, int N, int _input_vector_length, int _output_vector_length, int _vector_pitch, 
                    double *_weight, double *_inputs, double *_bias,
                    double alpha=1.0, double beta=1.0){
                    
                    int m = N;
                    int n = _output_vector_length;
                    int k = _input_vector_length;

                    int stride = _vector_pitch/sizeof(double);

                    checkCublasErrors( cublasDgemm(cublasHandle, CUBLAS_OP_N, CUBLAS_OP_T,
                                        m,n,k,
                                        &alpha,
                                        _inputs, stride,
                                        _weight, n,
                                        &beta,
                                        _bias, stride));           
     };
};

template <>
struct gemm<float>{
     gemm<float> ( cublasHandle_t cublasHandle, int N, int _input_vector_length, int _output_vector_length, int _vector_pitch, 
                    const float *_weight, const float *_inputs, float *_bias,
                    float alpha=1.0, float beta=1.0){

                    int m = N;
                    int n = _output_vector_length;
                    int k = _input_vector_length;

                    int stride = _vector_pitch/sizeof(double);

                     checkCublasErrors( cublasSgemm(cublasHandle, CUBLAS_OP_N, CUBLAS_OP_T,
                                        m,n,k,
                                        &alpha,
                                        _inputs, stride,
                                        _weight, n,
                                        &beta,
                                        _bias, stride)); 
     };
};

// ==================================================================================================================================
//
// Network Algorithem class
// cudnn/cublas handles are initialized when this class is constructed.
//
// Notice: one sample data input is a row vector [1 x width].
// and N samples form a matrix [N x w].
// Therefore, the most optimized solution is to using a 2D-Tensor holding the matrix.
// However, cudnn limits the lowest tensor dimension to 3D, so one need an extra dimension (height, or h) to utilize cudnn TensorDesciptor
// In fact, it does NOT matter how to setup h and w, but only to make sure  ( h * w == num_of_data_in_one_sample_vector )
//
// Offered methods :
//                       fullyConnectedForward(layer, N, h, w, float/double* srcData, f/d** dstData)
//                       softmaxForward(n, h, w, * srcData, ** dstData)
//                       activiationforward_tanh (n, h, w, * srcData, ** dstData)
//                       activiationforward_ReLU (n, h, w, * srcData, ** dstData)

template <typename T>
class network_t
{
private:

    cudnnDataType_t dataType;      // specify the data type CUDNN refers to, in {16-bit, 32-bit, 64-bit} floating point 
 
    cudnnHandle_t cudnnHandle;     // a pointer to a structure holding the CUDNN library context
                                   // Must be created via "cudnnCreate()" and destroyed at the end by "cudnnDestroy()"
                                   // Must be passed to ALL subsequent library functions!!!

    cublasHandle_t cublasHandle;   // cublas handle, similar as above cudnn_handle

    // Opaque tensor descriptors (N-dim matrix), for operations of layers
    cudnnTensorDescriptor_t srcTensorDesc, dstTensorDesc, biasTensorDesc;

    cudnnActivationDescriptor_t  activDesc; // Activiation type used in CUDNN

    
    // create and destroy handles/descriptors, note the sequence of creating/destroying
    void createHandles()
    {
        checkCUDNN( cudnnCreate(&cudnnHandle) ); 
        checkCUDNN( cudnnCreateTensorDescriptor(&srcTensorDesc) );
        checkCUDNN( cudnnCreateTensorDescriptor(&dstTensorDesc) );
        checkCUDNN( cudnnCreateTensorDescriptor(&biasTensorDesc) );
        checkCUDNN( cudnnCreateActivationDescriptor(&activDesc) );
        checkCublasErrors( cublasCreate(&cublasHandle) );
    }
    void destroyHandles()
    {
        checkCUDNN( cudnnDestroyActivationDescriptor(activDesc) );
        checkCUDNN( cudnnDestroyTensorDescriptor(srcTensorDesc) );
        checkCUDNN( cudnnDestroyTensorDescriptor(dstTensorDesc) );
        checkCUDNN( cudnnDestroyTensorDescriptor(biasTensorDesc) );
        checkCUDNN( cudnnDestroy(cudnnHandle) );
        checkCublasErrors( cublasDestroy(cublasHandle) );
    }

     // Setting tensor descriptor
     void setTensorDesc(cudnnTensorDescriptor_t& tensorDesc, 
                         cudnnDataType_t& dataType,
                         int n,    // number of batch samples
                         int h,    // rows of one sample
                         int w)    // cols of one sample
     {
         const int nDims = 3;           
         int dimA[nDims] = {n,h,w};
         int strideA[nDims] = {h*w, w, 1}; // stride for each dimension
         checkCUDNN( cudnnSetTensorNdDescriptor(tensorDesc,
                                                 dataType,
                                                 3,
                                                 dimA,
                                                 strideA ) ); 
     }

     // Setting tensor descriptor 4D (=1 in the last dimension)
     void setTensorDesc4D(cudnnTensorDescriptor_t& tensorDesc, 
                         cudnnDataType_t& dataType,
                         int n,    // number of batch samples
                         int h,    // rows of one sample
                         int w)    // cols of one sample
     {
         const int nDims = 4;           
         int dimA[nDims] = {n,h,w,1};
         int strideA[nDims] = {h*w, w, 1,1}; // stride for each dimension
         checkCUDNN( cudnnSetTensorNdDescriptor(tensorDesc,
                                                 dataType,
                                                 4,
                                                 dimA,
                                                 strideA ) ); 
     }     

      
  public:
    network_t<T>()
    {     
          if ( TypeIsDouble<T>::value ) {  
               dataType = CUDNN_DATA_DOUBLE;
          } else if ( TypeIsFloat<T>::value ) {
               dataType = CUDNN_DATA_FLOAT;          
          } else {
               cout << " Data type is not single/double precision float ! ERROR! " <<endl;
          }
      
        createHandles();    
    };
    ~network_t<T>()
    {
        destroyHandles();
    }
    
    // Resize device memory and initialize to 0
    void resize(int size, T **data)
    {
        if (*data != NULL)
        {
            checkCudaErrors( cudaFree(*data) );
        }
        checkCudaErrors( cudaMalloc(data, size*sizeof(T)) );
        checkCudaErrors( cudaMemset(*data, 0, size*sizeof(T)) );        
    }
    
    
    // add bias into the destination Descriptor
    // Note, "cudnnAddTensor" returns error "CUDNN_STATUS_NOT_SUPPORTED" 
    // if the TensorDescs are initialized as 3D Tensor. So they are set to 4D,
    // with one extra dimension (= 1 in size, of course).
    void addBias(const Layer_t<T>& layer, int _n, int _h, int _w, T *dstdata)
    {
        setTensorDesc4D(biasTensorDesc, dataType,  1, _h, _w);
        setTensorDesc4D(dstTensorDesc,  dataType, _w, _h, _n);
        T alpha = 1.0;
        T beta  = 1.0;
        
        checkCUDNN( cudnnAddTensor( cudnnHandle, 
                                    &alpha, biasTensorDesc,
                                    layer.bias_d,
                                    &beta,
                                    dstTensorDesc,
                                    dstdata) );
          
    }        
    
  
    // Fully connected forwards, using cublas only
    void fullyConnectedForward(const Layer_t<T>& layer,
                          int& n, size_t & pitch, int& h, int& w,
                          T* srcData, T** dstData)
    {     
        int dim_x = h * w;
        int dim_y = layer.outputs;
        int strideDim = pitch/sizeof(T);
        resize(strideDim*dim_y, dstData);
        
        // add bias into dstData
        addBias( layer, strideDim, dim_y, 1, *dstData);

        // perform forward calculation
        gemm<T>(cublasHandle,n, dim_x, dim_y, pitch, layer.data_d, srcData, *dstData);

        // for future ease, set h = total_num_of_ele_in_output, and w = 1
        h = dim_y; w = 1; 
    } 


 
    // Softmax forwards from CUDNN
    void softmaxForward(int n, int h, int w, T* srcData, T** dstData)
    {
        resize(n*h*w, dstData);

        setTensorDesc(srcTensorDesc, dataType, n, h, w);
        setTensorDesc(dstTensorDesc, dataType, n, h, w);

        T alpha = 1.0;
        T beta  = 0.0;
        checkCUDNN( cudnnSoftmaxForward(cudnnHandle,
                                          CUDNN_SOFTMAX_FAST ,
                                          CUDNN_SOFTMAX_MODE_CHANNEL,
                                          &alpha,
                                          srcTensorDesc,
                                          srcData,
                                          &beta,
                                          dstTensorDesc,
                                          *dstData) );
    }
    
    // activation forward with hyperbolic tangential
    void activationForward_TANH(int n, int h, int w, T* srcData, T** dstData, size_t pitch)
    {
        checkCUDNN( cudnnSetActivationDescriptor(activDesc,
                                                CUDNN_ACTIVATION_TANH,
                                                CUDNN_PROPAGATE_NAN,
                                                0.0) );    
        int stride = pitch/sizeof(T);     
    
        resize(stride*h*w, dstData);

        setTensorDesc(srcTensorDesc, dataType, stride, h, w);
        setTensorDesc(dstTensorDesc, dataType, stride, h, w);

        T alpha = 1.0;
        T beta  = 0.0;
        checkCUDNN( cudnnActivationForward(cudnnHandle,
                                            activDesc,
                                            &alpha,
                                            srcTensorDesc,
                                            srcData,
                                            &beta,
                                            dstTensorDesc,
                                            *dstData) );   
    }

    
    // activation forward with ReLU nonlinearty    
    void activationForward_ReLU(int n, int h, int w, T* srcData, T** dstData)
    {
        checkCUDNN( cudnnSetActivationDescriptor(activDesc,
                                                CUDNN_ACTIVATION_RELU,
                                                CUDNN_PROPAGATE_NAN,
                                                0.0) );   
        resize(n*h*w, dstData);

        setTensorDesc(srcTensorDesc, dataType, n, h, w);
        setTensorDesc(dstTensorDesc, dataType, n, h, w);

        T alpha = 1.0;
        T beta  = 0.0;
        checkCUDNN( cudnnActivationForward(cudnnHandle,
                                            activDesc,
                                            &alpha,
                                            srcTensorDesc,
                                            srcData,
                                            &beta,
                                            dstTensorDesc,
                                            *dstData) );    
    }    

};


//===========================================================================================
//
// Model of all layers (as a double linked list), combined with forward prediction
// 
template <typename T>
class Layer_Net_t{
private:

     // network algorithm initialize with constructor
     // Note, as nVidia suggested, it is best practice to let all cuda context live 
     // as long as the application without frequent create/destroy
     network_t<T> neural_net;
     
     void switchptr(T** & alpha, T** & bravo){
          T** tmp;
          tmp = alpha;
          alpha = bravo;
          bravo = tmp;
          tmp = nullptr;
     }

public:
     Layer_t<T>* root = nullptr;
    
     Layer_Net_t<T>(){};
     
     ~Layer_Net_t<T>(){
          Layer_t<T>* curr = nullptr;
          if (root!= NULL) {
               curr = root;
               while(curr->next){curr = curr->next;} ;
               while(curr->prev){
                    curr = curr->prev;
                    delete curr->next;
                    curr->next =nullptr;
               }
               curr = nullptr;
               delete root;
               root = nullptr;
          }
     };    
     
     // Inserting a dense layer
     void insert_layer(string &_name, int _inputs, int _outputs, 
          T*& _data_h, T*& _bias_h){
          if (root!=NULL) {
               Layer_t<T>* curr = root;
               while(curr->next) {curr = curr->next;};
               curr->next = new Layer_t<T>(_name, _inputs, _outputs, _data_h, _bias_h);
               curr->next->prev = curr;
          } else {
               root = new Layer_t<T>(_name, _inputs, _outputs, _data_h, _bias_h);
          };
     
     };
     
     // Inserting an activiation layer by type (int)
     void insert_layer(string &_name, int _acttype){
          if (root!=NULL) {
               Layer_t<T>* curr = root;
               while(curr->next) {curr = curr->next;};
               curr->next = new Layer_t<T>(_name, _acttype);
               curr->next->prev = curr;
          } else {
               root = new Layer_t<T>(_name, _acttype);
          };
     
     };     
     
     // Inserting an activiation layer by type (name)
     void insert_layer(string &_name, ActType_t _acttype){
          if (root!=NULL) {
               Layer_t<T>* curr = root;
               while(curr->next) {curr = curr->next;};
               curr->next = new Layer_t<T>(_name, _acttype);
               curr->next->prev = curr;
          } else {
               root = new Layer_t<T>(_name, _acttype);
          };
     
     };      
     
     // Get layer ptr according to its index (start from 1 as 1st layer, 2 as seond layer ...)
     Layer_t<T>* get_layer_by_seq(int _n){
          Layer_t<T>* curr=root;
          int i = 1;
          
          while( (curr->next != NULL)  && (i<_n) ){
               curr = curr->next;
               i++ ;
          };
          return curr;
     }
     
     // Make prediction according to all the layers in the model
     void predict(T* _inputData, size_t pitch, int _n, int _w, T* & _outputData_h, unsigned long int& _outsize){
        
        if (root != NULL) {
             //cout<<"N: "<<_n<<"W: "<<_w<<endl;
             int n,h,w;   // number of sampels in one batch ; height ; width 
             
             T *devData_alpha = nullptr, *devData_bravo = nullptr;  // two storage places (alpha and bravo) saving data flow
             
             // two ptrs towards either alpha or bravo
             // controlling from which the data is read
             // and to which the result is written to 
             T** srcDataPtr = nullptr, **dstDataPtr = nullptr; 

             
             // initialize storage alpha and save input vector into it
             //cout << " Initializing input data ... " << endl;               
             n = _n; h = 1; w = _w;               
             //checkCudaErrors( cudaMalloc(&devData_alpha, n*h*w*sizeof(T)) );
             //checkCudaErrors( cudaMemcpy( devData_alpha, _inputData,
             //                            n*h*w*sizeof(T),
             //                             cudaMemcpyHostToDevice) );
             
             devData_alpha = _inputData;
             srcDataPtr = &devData_alpha;
             dstDataPtr = &devData_bravo;
                                  
             Layer_t<T>* curr = root;
             do{
               cout<<curr->name<<endl;

               //cout << " Processing Layer : " << curr->name << endl;
               if ( curr-> type == Type_t::DENSE ) { 
                    // If it is a dense layer, we perform fully_connected forward 
                    neural_net.fullyConnectedForward((*curr), n, pitch, h, w, *srcDataPtr, dstDataPtr);
                    // Swith the origin/target memory array after the step
                    switchptr(srcDataPtr, dstDataPtr);
                      
               } else if (curr -> type == Type_t::ACTIVIATION){
                    // If it is an activiation layer, perform corresponding activiation forwards
                    // In fact, activiation::linear = doing NOTHING 
                    if (curr -> acttype == ActType_t::TANH){
                         neural_net.activationForward_TANH(n, h, w, *srcDataPtr, dstDataPtr, pitch);
                         switchptr(srcDataPtr, dstDataPtr);
                    } else if (curr->acttype != ActType_t::LINEAR) {    
                         cout << "Unknown activation type!" <<endl;
                    } 
               } else {
                    cout << "Unknown layer type!" <<endl;
               }

             } while(  (curr=curr->next) != NULL);
             
             //cout << "Final score : " ;        
             //printDeviceVector<T>(n*h*w, *srcDataPtr);
             
             _outsize=n*h*w;
             if(_outputData_h!=NULL){
                    delete[] _outputData_h;
             }
             _outputData_h = new T[_outsize];
             cudaDeviceSynchronize();

             cudaMemcpy(_outputData_h, *srcDataPtr, _outsize*sizeof(T), cudaMemcpyDeviceToHost);            
             
             
             // Don't forget to release resource !!!
             srcDataPtr = nullptr;
             dstDataPtr = nullptr;
              
             checkCudaErrors( cudaFree(devData_alpha) );
             checkCudaErrors( cudaFree(devData_bravo) );
        
        }
        return;
         
     } 
};

//Structure to hold all the different networks needed after they are built
template<typename T>
struct allNets_t{
     Layer_Net_t<T> * nets;
     size_t  numNetworks;

     //Default constructor
     allNets_t(): nets(nullptr), numNetworks(0) {}

     //Construct from HDF5 file
     allNets_t(size_t _numNetworks, const char* filename, const char* checkchar)
     :numNetworks(_numNetworks){

          nets = new Layer_Net_t<T>[numNetworks];
          H5::H5File file(filename,H5F_ACC_RDONLY);

          hsize_t data_rank=0;
          hsize_t* data_dims = nullptr;
          T* data = nullptr;     
          hsize_t bias_rank=0;
          hsize_t* bias_dims = nullptr;
          T* bias = nullptr;

          vector<string> sequence;
          sequence = Read_Attr_Data_By_Seq(file,PATHTOMODEL, LAYERNAMES); 

          string networkNum, networkName;
          int currentNetNum = 0;


      
          networkNum = std::to_string(currentNetNum +1);
          networkName = "sequential_"+ networkNum;

          int layerID=1; 
          for(auto it=sequence.begin();it!=sequence.end();it++){
               string seqPath = mkpath ( string(PATHTOMODEL),  *it );
               if(*it == networkName){
                    // get this layer's dataset names(weights and bias)
                    vector<string> weights;
                    weights = Read_Attr_Data_By_Seq(file,seqPath.c_str(), WEIGHTNAMES);
                    cout<<*it<<endl;

                    cout << " Reading out data: " << *it << endl;
                    for (auto it2 = weights.begin(); it2 != weights.end(); it2++){ 
                         // for one data set get path
                         string datasetPath = mkpath(seqPath,*it2) ;
                    
                         //Dense Layer Name
                         string DLname = (*it2).substr(0,7);

                         // check the dataset name's last character to see if this dataset is a Weight or a Bias
                         if ((*it2).compare(((*it2).length()-1),1, checkchar )==0){
                              
                              // get out weight data
                              Read_Layer_Data_By_DatName<T> (file, datasetPath.c_str(), data, data_rank, data_dims); 
                         }
                         else{
                              // get out bias data
                              Read_Layer_Data_By_DatName<T> (file, datasetPath.c_str(), bias, bias_rank, bias_dims);\
                              cout << " Initialize layer : " << DLname << endl;
                         
                              nets[currentNetNum].insert_layer(DLname, data_dims[0], data_dims[1], data, bias);

                              cout << " Layer " << DLname << "  is initialized. " <<endl <<endl; 


                              //insert tanh activation layer afterwards
                              string actName = "Activation_" + to_string(layerID/2);
                              
                              cout << " Initialize layer : " << actName << endl;
                              nets[currentNetNum].insert_layer(actName, ActType_t::TANH);
                              cout << " Layer " << actName << "  is initialized. " <<endl <<endl;                                    
                    
                              //reset values for next loop
                              data_rank=0;
                              bias_rank=0; 
                        }
                        
                        layerID++;

                    }

                    //make last layer activation type linear
                    nets[currentNetNum].get_layer_by_seq(layerID) -> acttype=ActType_t::LINEAR;
                    cout<<"Changing Layer "<<nets[currentNetNum].get_layer_by_seq(layerID)->name<<" to Linear Activation"<<endl;
                    cout << "Inserting Layers " << *it<< " Finished!"  <<endl;

                    currentNetNum++;
                  
                    networkNum = std::to_string(currentNetNum +1);
                    networkName = "sequential_"+ networkNum;   
               }
          }
          // Free memory of allocated arrays.
          if(bias!=NULL)       delete[] bias;
          if(bias_dims!=NULL)  delete[] bias_dims;
          if(data!=NULL)       delete[] data;
          if(data_dims!=NULL)  delete[] data_dims;      
          file.close();
          return;

     }

     //Destructor
     ~allNets_t(){
          delete [] nets;
     }


     void runAllNets(Gfunction_t<T> * gf, T * finalOutput){
          double * output = nullptr;
          size_t outsize = 0;
          size_t N = gf->NCluster;
          for(int i = 0; i< gf->model.NATOM; i++){
               size_t currAtomType = gf->model.TYPE_EACHATOM[i];
               cout<<"Running Network for "<<currAtomType<< " Atom "<<i<<" : "<<endl;
               nets[currAtomType].predict(gf->G_d[i]->dat,gf->G_d[i]->pitch,N,
                    gf->G_param_max_size[currAtomType], output, outsize);
               for(int a = 0; a< N; a++){
                    finalOutput[a] += output[a];
                    cout<<output[a]<<endl;

               }
          }

          double * cutoffs = nullptr;
          cutoffs = (double*)malloc(N*sizeof(double));
          cudaMemcpy(cutoffs, gf->cutoffs, N*sizeof(double),cudaMemcpyDeviceToHost);
          for(int a = 0; a<N; a++){
               finalOutput[a]*= cutoffs[a]*(EUNIT);
          }

          if(output!=NULL) delete[] output;  

     }


};



#endif
