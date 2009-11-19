/*
 * Copyright 1993-2007 NVIDIA Corporation.  All rights reserved.
 *
 * NOTICE TO USER:
 *
 * This source code is subject to NVIDIA ownership rights under U.S. and
 * international Copyright laws.  Users and possessors of this source code
 * are hereby granted a nonexclusive, royalty-free license to use this code
 * in individual and commercial software.
 *
 * NVIDIA MAKES NO REPRESENTATION ABOUT THE SUITABILITY OF THIS SOURCE
 * CODE FOR ANY PURPOSE.  IT IS PROVIDED "AS IS" WITHOUT EXPRESS OR
 * IMPLIED WARRANTY OF ANY KIND.  NVIDIA DISCLAIMS ALL WARRANTIES WITH
 * REGARD TO THIS SOURCE CODE, INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY, NONINFRINGEMENT, AND FITNESS FOR A PARTICULAR PURPOSE.
 * IN NO EVENT SHALL NVIDIA BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL,
 * OR CONSEQUENTIAL DAMAGES, OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
 * OF USE, DATA OR PROFITS,  WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE
 * OR OTHER TORTIOUS ACTION,  ARISING OUT OF OR IN CONNECTION WITH THE USE
 * OR PERFORMANCE OF THIS SOURCE CODE.
 *
 * U.S. Government End Users.   This source code is a "commercial item" as
 * that term is defined at  48 C.F.R. 2.101 (OCT 1995), consisting  of
 * "commercial computer  software"  and "commercial computer software
 * documentation" as such terms are  used in 48 C.F.R. 12.212 (SEPT 1995)
 * and is provided to the U.S. Government only as a commercial end item.
 * Consistent with 48 C.F.R.12.212 and 48 C.F.R. 227.7202-1 through
 * 227.7202-4 (JUNE 1995), all U.S. Government End Users acquire the
 * source code with only those rights set forth herein.
 *
 * Any use of this source code in individual and commercial software must
 * include, in the user documentation and internal comments to the code,
 * the above Disclaimer and U.S. Government End Users Notice.
 */

/* Template project which demonstrates the basics on how to setup a project 
 * example application.
 * Device code.
 */

#define COVARIANCE_DYNAMIC_RANGE 1E6

#ifndef _TEMPLATE_KERNEL_H_
#define _TEMPLATE_KERNEL_H_

#include <stdio.h>
#include "gaussian.h"

#define sdata(index)      CUT_BANK_CHECKER(sdata, index)

/*
 * Compute the multivariate mean of the FCS data
 */ 
__device__ void mvtmeans(float* fcs_data, int num_dimensions, int num_events, float* means) {
    // access thread id
    int tid = threadIdx.x;

    if(tid < num_dimensions) {
        means[tid] = 0.0;
    }

    __syncthreads();

    // Sum up all the values for the dimension
    for(int i=0; i < num_events; i++) {
        if(tid < num_dimensions) {
            //means[tid] += fcs_data[tid*num_events+i];
            means[tid] += fcs_data[i*num_dimensions+tid];
        }  
    }
    
    __syncthreads();

    // Divide by the # of elements to get the average
    if(tid < num_dimensions) {
        means[tid] /= (float) num_events;
    }
}

__device__ void averageVariance(float* fcs_data, float* means, int num_dimensions, int num_events, float* avgvar) {
    // access thread id
    int tid = threadIdx.x;
    
    __shared__ float variances[NUM_DIMENSIONS];
    __shared__ float total_variance;
    
    // Compute average variance for each dimension
    if(tid < num_dimensions) {
        variances[tid] = 0.0;
        // Sum up all the variance
        for(int j=0; j < num_events; j++) {
            // variance = (data - mean)^2
            variances[tid] += (fcs_data[j*num_dimensions + tid])*(fcs_data[j*num_dimensions + tid]);
        }
        variances[tid] /= (float) num_events;
        variances[tid] -= means[tid]*means[tid];
    }
    
    __syncthreads();
    
    if(tid == 0) {
        total_variance = 0.0;
        for(int i=0; i<num_dimensions;i++) {
            ////printf("%f ",variances[tid]);
            total_variance += variances[i];
        }
        ////printf("\nTotal variance: %f\n",total_variance);
        *avgvar = total_variance / (float) num_dimensions;
        ////printf("Average Variance: %f\n",*avgvar);
    }
}

// Inverts an NxN matrix 'data' stored as a 1D array in-place
// 'actualsize' is N
// Computes the log of the determinant of the origianl matrix in the process
__device__ void invert(float* data, int actualsize, float* log_determinant)  {
    int maxsize = actualsize;
    int n = actualsize;
    
    if(threadIdx.x == 0) {
        *log_determinant = 0.0;

#if EMU
            EMUPRINT("\n\nR matrix before inversion:\n");
            for(int i=0; i<n; i++) {
                for(int j=0; j<n; j++) {
                    EMUPRINT("%.2f ",data[i*n+j]);
                }
                EMUPRINT("\n");
            }
#endif

      // sanity check        
      if (actualsize == 1) {
        *log_determinant = logf(data[0]);
        data[0] = 1.0 / data[0];
      } else {

          for (int i=1; i < actualsize; i++) data[i] /= data[0]; // normalize row 0
          for (int i=1; i < actualsize; i++)  { 
            for (int j=i; j < actualsize; j++)  { // do a column of L
              float sum = 0.0;
              for (int k = 0; k < i; k++)  
                  sum += data[j*maxsize+k] * data[k*maxsize+i];
              data[j*maxsize+i] -= sum;
              }
            if (i == actualsize-1) continue;
            for (int j=i+1; j < actualsize; j++)  {  // do a row of U
              float sum = 0.0;
              for (int k = 0; k < i; k++)
                  sum += data[i*maxsize+k]*data[k*maxsize+j];
              data[i*maxsize+j] = 
                 (data[i*maxsize+j]-sum) / data[i*maxsize+i];
              }
            }
            
            for(int i=0; i<actualsize; i++) {
                *log_determinant += logf(fabs(data[i*n+i]));
            }
    #if EMU
                EMUPRINT("Determinant: %E\n",*log_determinant);
    #endif
            
          for ( int i = 0; i < actualsize; i++ )  // invert L
            for ( int j = i; j < actualsize; j++ )  {
              float x = 1.0;
              if ( i != j ) {
                x = 0.0;
                for ( int k = i; k < j; k++ ) 
                    x -= data[j*maxsize+k]*data[k*maxsize+i];
                }
              data[j*maxsize+i] = x / data[j*maxsize+j];
              }
          for ( int i = 0; i < actualsize; i++ )   // invert U
            for ( int j = i; j < actualsize; j++ )  {
              if ( i == j ) continue;
              float sum = 0.0;
              for ( int k = i; k < j; k++ )
                  sum += data[k*maxsize+j]*( (i==k) ? 1.0 : data[i*maxsize+k] );
              data[i*maxsize+j] = -sum;
              }
          for ( int i = 0; i < actualsize; i++ )   // final inversion
            for ( int j = 0; j < actualsize; j++ )  {
              float sum = 0.0;
              for ( int k = ((i>j)?i:j); k < actualsize; k++ )  
                  sum += ((j==k)?1.0:data[j*maxsize+k])*data[k*maxsize+i];
              data[j*maxsize+i] = sum;
              }
          
    #if EMU
          EMUPRINT("\n\nR matrix after inversion:\n");
          for(int i=0; i<n; i++) {
              for(int j=0; j<n; j++) {
                  EMUPRINT("%.2f ",data[i*n+j]);
              }
              EMUPRINT("\n");
          }
    #endif
        }
    }
 }


__device__ void normalize_pi(cluster* clusters, int num_clusters) {
    __shared__ float sum;
    
    // TODO: could maybe use a parallel reduction..but the # of elements is really small
    // What is better: having thread 0 compute a shared sum and sync, or just have each one compute the sum?
    if(threadIdx.x == 0) {
        sum = 0.0;
        for(int i=0; i<num_clusters; i++) {
            sum += clusters[i].pi;
        }
    }
    
    __syncthreads();
    
    if(threadIdx.x < num_clusters) {
        if(sum > 0.0) {
            clusters[threadIdx.x].pi /= sum;
        } else {
            clusters[threadIdx.x].pi = 0.0;
        }
    }
    
    __syncthreads();
}


__device__ void compute_constants(cluster* clusters, int num_clusters, int num_dimensions) {
    int tid = threadIdx.x;
    int num_threads = blockDim.x;
    int num_elements = num_dimensions*num_dimensions;
    
    __shared__ float determinant_arg; // only one thread computes the inverse so we need a shared argument
    
    float log_determinant;
    
    __shared__ float matrix[NUM_DIMENSIONS*NUM_DIMENSIONS];
    
    // Invert the matrix for every cluster
    int c = blockIdx.x;
    // Copy the R matrix into shared memory for doing the matrix inversion
    for(int i=tid; i<num_elements; i+= num_threads ) {
        matrix[i] = clusters[c].R[i];
    }
    
    __syncthreads(); 
    
    invert(matrix,num_dimensions,&determinant_arg);

    __syncthreads(); 
    
    log_determinant = determinant_arg;
    
    // Copy the matrx from shared memory back into the cluster memory
    for(int i=tid; i<num_elements; i+= num_threads) {
        clusters[c].Rinv[i] = matrix[i];
    }
    
    __syncthreads();
    
    // Compute the constant
    // Equivilent to: log(1/((2*PI)^(M/2)*det(R)^(1/2)))
    // This constant is used in all E-step likelihood calculations
    if(tid == 0) {
        clusters[c].constant = -num_dimensions*0.5*logf(2*PI) - 0.5*log_determinant;
    }
}

////////////////////////////////////////////////////////////////////////////////
//! @param fcs_data         FCS data: [num_events]
//! @param clusters         Clusters: [num_clusters]
//! @param num_dimensions   number of dimensions in an FCS event
//! @param num_events       number of FCS events
////////////////////////////////////////////////////////////////////////////////
__global__ void
seed_clusters( float* fcs_data, cluster* clusters, int num_dimensions, int num_clusters, int num_events) 
{
    // access thread id
    int tid = threadIdx.x;
    // access number of threads in this block
    int num_threads = blockDim.x;

    // shared memory
    __shared__ float means[NUM_DIMENSIONS];
    
    // Compute the means
    mvtmeans(fcs_data, num_dimensions, num_events, means);

    __syncthreads();
    
    float avgvar;
    
    // Compute the average variance
    averageVariance(fcs_data, means, num_dimensions, num_events, &avgvar);
        
    // Initialize covariances
    __shared__ float covs[NUM_DIMENSIONS*NUM_DIMENSIONS]; 
    
    int num_elements;
    int row, col;
        
    // Number of elements in the covariance matrix
    num_elements = num_dimensions*num_dimensions; 

    __syncthreads();

    float sum;

    // Compute the initial covariance matrix of the data
    for(int i=tid; i < num_elements; i+= num_threads) {
            // zero the value, find what row and col this thread is computing
            sum = 0.0;
            row = (i) / num_dimensions;
            col = (i) % num_dimensions;

            for(int j=0; j < num_events; j++) {
                sum += (fcs_data[j*num_dimensions+row])*(fcs_data[j*num_dimensions+col]); 
            }
            sum = sum / (float) num_events;
            sum = sum - means[row]*means[col];

            covs[i] = sum;
    } 
    __syncthreads();    
    
    // Calculate a seed value for the means
    float seed;
    if(num_clusters > 1) {
        seed = (num_events-1.0)/(num_clusters-1.0);
    } else {
        seed = 0.0;
    }
    
    // Seed the pi, means, and covariances for every cluster
    for(int c=0; c < num_clusters; c++) {
        clusters[c].pi = 1.0/((float)num_clusters);
        clusters[c].N = ((float) num_events) / ((float)num_clusters);
        if(tid < num_dimensions) {
            clusters[c].means[tid] = fcs_data[((int)(c*seed))*num_dimensions+tid];
            //clusters[c].means[tid] = means[tid];
        }
          
        for(int i=tid; i < num_elements; i+= num_threads) {
            // Add the average variance divided by a constant, this keeps the cov matrix from becoming singular
            clusters[c].R[i] = covs[i] + avgvar/COVARIANCE_DYNAMIC_RANGE;
        }
        if(tid == 0) {
            clusters[c].avgvar = avgvar / COVARIANCE_DYNAMIC_RANGE;
        }
    }
}

__global__ void
regroup(float* fcs_data, cluster* clusters, float* memberships, int num_dimensions, int num_clusters, int num_events, float* likelihood) {
    float like;
    float max_likelihood;
    float denominator_sum;
    float temp;
    float thread_likelihood = 0.0f;
    __shared__ float total_likelihoods[NUM_THREADS];
    
    // Cached cluster parameters
    __shared__ float means[NUM_DIMENSIONS];
    __shared__ float Rinv[NUM_DIMENSIONS*NUM_DIMENSIONS];
    float cluster_pi;
    float constant;
 
    int num_threads = blockDim.x;
    int num_pixels_per_block = num_events / NUM_BLOCKS;  
    int tid = threadIdx.x;
    
    int start_index;
    int end_index;
    start_index = blockIdx.x * num_pixels_per_block + tid;
    
    if(blockIdx.x == NUM_BLOCKS-1) {
        end_index = num_events;
    } else {
        end_index = (blockIdx.x+1) * num_pixels_per_block;
    }
    
    //printf("Block Index: %d, Thread Index: %d, start_index: %d, end_index: %d\n",blockIdx.x,tid,start_index,end_index);

    total_likelihoods[tid] = 0.0;

    // This loop computes the expectation of every event into every cluster
    //
    // P(k|n) = L(x_n|mu_k,R_k)*P(k) / P(x_n)
    //
    // Compute log-likelihood for every cluster for each event
    // L = constant*exp(-0.5*(x-mu)*Rinv*(x-mu))
    // log_L = log_constant - 0.5*(x-u)*Rinv*(x-mu)
    // the constant stored in clusters[c].constant is already the log of the constant
    for(int c=0; c<num_clusters; c++) {
        // copy the means for this cluster into shared memory
        if(tid < num_dimensions) {
            means[tid] = clusters[c].means[tid];
        }

        // copy the covariance inverse into shared memory
        for(int i=tid; i < num_dimensions*num_dimensions; i+= num_threads) {
            Rinv[i] = clusters[c].Rinv[i]; 
        }

        // Sync to wait for all params to be loaded to shared memory
        __syncthreads();

        cluster_pi = clusters[c].pi;
        constant = clusters[c].constant;
        
        for(int event=start_index; event<end_index; event += num_threads) {
            like = 0.0;
            // this does the loglikelihood calculation
            for(int i=0; i<num_dimensions; i++) {
                for(int j=0; j<num_dimensions; j++) {
                    like += (fcs_data[i*num_events+event]-means[i]) * (fcs_data[j*num_events+event]-means[j]) * Rinv[i*num_dimensions+j];
                    //like += (fcs_data[event*num_dimensions+i]-means[i]) * (fcs_data[event*num_dimensions+j]-means[j]) * Rinv[i*num_dimensions+j];
                    //like += (fcs_data[event*num_dimensions+i]-clusters[c].means[i])*(fcs_data[event*num_dimensions+j]-clusters[c].means[j])*clusters[c].Rinv[i*num_dimensions+j];
                }
            }
            memberships[c*num_events+event] = -0.5f * like + constant + logf(cluster_pi); // numerator of the probability computation
            //probs[event] = -0.5f * like + constant + logf(cluster_pi); // numerator of the probability computation
        }

        // Make sure all threads done with their pixels b4 moving to next cluster
        __syncthreads(); 
    }

    __syncthreads(); 
    
    // P(x_n) = sum of likelihoods weighted by P(k) (their probability, cluster[c].pi)
    // However we use logs to prevent under/overflow
    //  log-sum-exp formula:
    //  log(sum(exp(x_i)) = max(z) + log(sum(exp(z_i-max(z))))
    for(int pixel=start_index; pixel<end_index; pixel += num_threads) {
        // find the maximum likelihood for this event
        max_likelihood = memberships[pixel];
        for(int c=1; c<num_clusters; c++) {
            max_likelihood = fmaxf(max_likelihood,memberships[c*num_events+pixel]);
        }

        // Compute P(x_n), the denominator of the probability (sum of weighted likelihoods)
        denominator_sum = 0.0;
        for(int c=0; c<num_clusters; c++) {
            temp = expf(memberships[c*num_events+pixel]-max_likelihood);
            denominator_sum += temp;
        }
        temp = max_likelihood + logf(denominator_sum);
        thread_likelihood += temp;
        
        // Divide by denominator, also effectively normalize probabilities
        for(int c=0; c<num_clusters; c++) {
            memberships[c*num_events+pixel] = expf(memberships[c*num_events+pixel] - temp);
            //printf("Probability that pixel #%d is in cluster #%d: %f\n",pixel,c,clusters[c].p[pixel]);
        }
    }
    
    total_likelihoods[tid] = thread_likelihood;

    
    float retval = 0.0;
    
    __syncthreads();
    
    // Reduce all the total_likelihoods to a single total
    if(tid == 0) {
        for(int i=0; i<num_threads; i++) {
            retval += total_likelihoods[i];
        }
        likelihood[blockIdx.x] = retval;
    }
}


__device__ float parallelSum(float* data, const unsigned int ndata) {
  const unsigned int tid = threadIdx.x;
  float t;

  __syncthreads();

  // Butterfly sum.  ndata MUST be a power of 2.
  for(unsigned int bit = ndata >> 1; bit > 0; bit >>= 1) {
    t = data[tid] + data[tid^bit];  __syncthreads();
    data[tid] = t;                  __syncthreads();
  }
  return data[tid];
}

///////////////////////////////////////////////////////////////////////////
// Parallel reduction, for when all you want is the sum of a certain
// quantity computed for every 1 to N.  CODE should be something in terms
// of n.  The resulting sum will be placed in RESULT.
// tmp_buff, base_off, RESULT, and n must be previously defined, however 
// they will be overwritten during the execution of the macro.
#define REDUCE(N, CODE, RESULT)                                \
base_off = 0;                                                  \
RESULT = 0.0f;                                                 \
while (base_off + BLOCK_SIZE < N) {                            \
  n = base_off + tid;                                          \
  tmp_buff[tid] = CODE;                                        \
  RESULT += parallelSum(tmp_buff, BLOCK_SIZE);                 \
  base_off += BLOCK_SIZE;                                      \
}                                                              \
n = base_off + tid;                                            \
if (n < N) {tmp_buff[tid] = CODE;}                             \
else {tmp_buff[tid] = 0.0f;}                                   \
RESULT += parallelSum(tmp_buff, BLOCK_SIZE);
///////////////////////////////////////////////////////////////////////////



/*
 * This kernel re-computes the means, N (number of data points per cluster),
 * and R (covariance matrix). The computations for each cluster are independent
 * therefore each cluster can be computed by a different block
 *
 * This should be launched with num_clusters blocks
 */
__global__ void
mstep_means(float* fcs_data, cluster* clusters, float* memberships, int num_dimensions, int num_clusters, int num_events) {
    int tid = threadIdx.x;
    int num_threads = blockDim.x;
    int c = blockIdx.x;
 
    // assuming num_threads is an even multiple of the number of dimensions
    int events_per_iteration = num_threads / num_dimensions;
    int event_offset = tid / num_dimensions;
    
    // Need to store the sum computed by each thread so in the end
    // a single thread can reduce to get the final sum
    __shared__ float temp_sums[NUM_THREADS];
    __shared__ float probs[128];

    // Compute new N
    float sum = 0.0f;
    // Break all the events accross the threads, add up probabilities
    for(int event=tid; event < num_events; event += num_threads) {
        sum += memberships[c*num_events+event];
    }
    temp_sums[tid] = sum;
 
    __syncthreads();
    
    // Let the first thread add up all the intermediate sums
    if(tid == 0) {
        clusters[c].N = 0.0;
        for(int j=0; j<num_threads; j++) {
            clusters[c].N += temp_sums[j];
        }
        //printf("clusters[%d].N = %f\n",c,clusters[c].N);
        
        // Set PI to the # of expected items, and then normalize it later
        clusters[c].pi = clusters[c].N;
    }

    // Synchronize because threads need to use clusters[c].N for means calculation    
    __syncthreads();

    int active_threads = num_dimensions*events_per_iteration;
    int event = event_offset;

    // Compute means for each subcluster
    // All threads participate only if num_dimensions is an even multiple of num_threads
    // num_threads should be a multiple of 16 for the sake of performance
    if(tid < active_threads) {
        sum = 0.0;
        for(int i=tid; i < num_dimensions*num_events; i+= active_threads) {
            sum += fcs_data[i]*memberships[c*num_events+event];
            event += events_per_iteration;
        }
        temp_sums[tid] = sum;
    }
    
    __syncthreads();
    
    // reduce
    if(tid < num_dimensions) {
        for(int i=1; i < events_per_iteration; i++) {
            temp_sums[tid] += temp_sums[i*num_dimensions+tid];
        }
        clusters[c].means[tid] = temp_sums[tid] / clusters[c].N;
    }
}
    
/*
 * Computes the covariance matrices of the data (R matrix)
 * Must be launched with as many blocks as there are clusters
 * Each block handles one matrix
 */
__global__ void
mstep_covariance(float* fcs_data, cluster* clusters, float* memberships, int num_dimensions, int num_clusters, int num_events) {
    
    int tid = threadIdx.x; // easier variable name for our thread ID
    int num_threads = blockDim.x; // number of threads in the block
    int c = blockIdx.x; // what cluster is this block handling
 
    // Number of elements in the covariance matrix
    int num_elements = num_dimensions*num_dimensions;

    // Store the means in shared memory to speed up the covariance computations
    __shared__ float means[NUM_DIMENSIONS];
    // copy the means for this cluster into shared memory
    if(tid < num_dimensions) {
        means[tid] = clusters[c].means[tid];
    }

    // Sync to wait for all params to be loaded to shared memory
    __syncthreads();

    __shared__ float event[NUM_THREADS];
    
    float cov_sum = 0.0;
    int row,col;

    __shared__ float membership;

    // Compute the covariance matrix of the data
    for(int i=tid; i < num_elements; i+= num_threads) {
        // zero the value, find what row and col this thread is computing
        cov_sum = 0.0;
        row = (i) / num_dimensions;
        col = (i) % num_dimensions;

        for(int j=0; j < num_events; j++) {
            /*
            event[tid] = fcs_data[j*num_dimensions+tid]; // only need tid < num_dimensions, but this splits the warp
            if(tid == num_dimensions) {
                membership = memberships[c*num_events+j];
            }
            __syncthreads();*/

            cov_sum += (fcs_data[j*num_dimensions+row]-means[row])*(fcs_data[j*num_dimensions+col]-means[col])*memberships[c*num_events+j]; 
            //cov_sum += (event[row]-means[row])*(event[col]-means[col])*memberships[c*num_events+j]; 
            //cov_sum += (event[row]-means[row])*(event[col]-means[col])*membership; 
        }
        if(clusters[c].N >= 1.0) { // Does it need to be >=1, or just something non-zero?
            clusters[c].R[i] = cov_sum / clusters[c].N;
        } else {
            clusters[c].R[i] = 0.0; // what should the variance be for an empty cluster...?
        }
    }
    
    __syncthreads();

    // Regularize matrix - adds some variance to the diagonals
    // Helps keep covariance matrix non-singular (so it can be inverted)
    // The amount added is scaled down based on COVARIANCE_DYNAMIC_RANGE constant defined at top of this file
    if(tid < num_dimensions) {
        clusters[c].R[tid*num_dimensions+tid] += clusters[c].avgvar;
    }
}

/*
 * Computes the constant for each cluster and normalizes pi for every cluster
 * In the process it inverts R and finds the determinant
 * 
 * Needs to be launched with the number of blocks = number of clusters
 */
__global__ void
constants_kernel(cluster* clusters, int num_clusters, int num_dimensions) {
    compute_constants(clusters,num_clusters,num_dimensions);
    
    __syncthreads();
    
    if(blockIdx.x == 0) {
        normalize_pi(clusters,num_clusters);
    }
}

#endif // #ifndef _TEMPLATE_KERNEL_H_
