/*
 * John David Eriksen
 * EEL6763 Spring 2008
 * HW2
 *
 * integral.c 
 * 
 * Part A - Monte-Carlo integration using Send/Receive, Reduce, and Serial methods 
 *
 * Usage: integral a b N {1|2|3}
 *
 * Note: The final usage parameter is the "mode". Enter only 1, 2, or 3.
 *
 * 1: Send/Receive
 * 2: Reduce
 * 3: Serial
 */

#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <time.h>
#include "mpi.h"

double random_number(double bound_lower, double bound_upper);
double fun_calc(double x);
double send_recv(double a, double b, int N);
double reduce(double a, double b, int N);
double serial(double a, double b, int N);
void debug(char *message, int line);
int samples_calc(int N, int rank, int nodes_total);
double samples_proc(int N, int rank, int nodes_total, int lower_bound, int upper_bound);

main (int argc, char* argv[]) {
    int my_rank;
    double time_start, time_end, time_elapsed;
    double result;

    if (argc != 5) {
        printf("Usage: %s a b N {1|2|3}\n", argv[0]);
        exit(1); 
    }

    double a = atof(argv[1]);
    double b = atof(argv[2]);
    int N = atoi(argv[3]);
    int mode = atoi(argv[4]);

    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &my_rank);

    /* Seed the random number generator */
    srand(time(NULL) + my_rank);

    time_start = MPI_Wtime();

    switch (mode) {
        case 1:
            result = send_recv(a, b, N);
            break;
        case 2:
            result = reduce(a, b, N);
            break;
        case 3:
            result = serial(a, b, N);
            break;
    }

    time_end = MPI_Wtime();
    time_elapsed = time_end - time_start;
    
    if (my_rank == 0) {
        double test = 1;
        double test_result = 1;
        test_result = fun_calc(test);
        printf("result: %f time: %f\n", result, time_elapsed);
        printf("test: %f test_result: %f\n", test, test_result);
    }

    MPI_Finalize();
 
    exit(0);
}

/*
 * Execute calculation and return result
 * Called once per node
 */
double samples_proc(int N, int rank, int nodes_total, int lower_bound, int upper_bound) {
    double result = 0;
    int i, samples;
    char message[100];

    samples = samples_calc(N, rank, nodes_total); 

    for (i = 0; i < samples; i++) { 
        result += fun_calc(random_number(lower_bound, upper_bound));
    }

    return result;
}

/* 
 * Return a random position within the range examined by the integration function
 */
double random_number(double bound_lower, double bound_upper) {
    double rand_val = 0;

    rand_val = (double) rand() / (double) RAND_MAX;
    rand_val *= bound_upper - bound_lower;
    rand_val += bound_lower;
 
    return rand_val;
}

/*
 * Execute the integration function on a single sample
 */
double fun_calc(double x) {
    return (1.0 / (sqrt(2.0 * M_PI))) * exp(-1.0 * (pow(x, 2.0) / 2.0)); 
}

/*
 * Monte-Carlo integration using the Send/Receive communication paradigm
 */
double send_recv(double a, double b, int N) {
    int my_rank;
    int p;
    int source;
    int dest = 0;
    int tag = 0;
    double integral_local, integral_remote, result = 0; 
    char message[100];

    MPI_Status status;
    MPI_Comm_rank(MPI_COMM_WORLD, &my_rank);
    MPI_Comm_size(MPI_COMM_WORLD, &p);

    /* Perform work */
    integral_local = samples_proc(N, my_rank, p, a, b);

    //sprintf(message, "rank: %d", my_rank);
    //debug(message, __LINE__);

    if (my_rank == 0) {
        for (source = 1; source < p; source++) {
            /* Collect and sum results from slave nodes */
            MPI_Recv(&integral_remote, 1, MPI_DOUBLE, source, tag, MPI_COMM_WORLD, &status);
            result += integral_remote;

            //sprintf(message, "RECV rank: %d integral: %f", my_rank, integral_remote);
            //debug(message, __LINE__);
        }

        /* Perform final operations */
        result += integral_local;
        result *= ((b - a) / (double) N);
    }
    else {
        /* Report results to master node */
        MPI_Send(&integral_local, 1, MPI_DOUBLE, dest, tag, MPI_COMM_WORLD);

        //sprintf(message, "SEND rank: %d integral: %f", my_rank, integral_local);
        //debug(message, __LINE__);
    }

    return result;
}

/*
 * Monte-Carlo integration using the Reduce communication paradigm
 */
double reduce(double a, double b, int N) {
    int my_rank;
    int p;
    int source;
    int dest = 0;
    int tag = 0;
    double result_local, result;
    char message[100];

    MPI_Status status;
    MPI_Comm_rank(MPI_COMM_WORLD, &my_rank);
    MPI_Comm_size(MPI_COMM_WORLD, &p);

    /* Perform work */
    result_local = samples_proc(N, my_rank, p, a, b);

    /* Obtain results from all nodes and sum them */
    MPI_Reduce(&result_local, &result, 1, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD);
    
    /* Perform final operation and report results */
    if (my_rank == 0) {
        result *= ((b - a) / (double) N);
    }

    return result;
}

/*
 * Serial version of the integration algorithm
 * For use in debugging and for performance comparison
 */
double serial(double a, double b, int N) {
    double result = 0;
    int i;

    for (i = 0; i < N; i++) {
        result += fun_calc(random_number(a, b));
    }
 
    result *= ((b - a) / (double) N);

    return result;
}

/*
 * Format and print debugging messages
 */
void debug(char *message, int line) {
    printf("%d: %s\n", line, message);
}

/*
 * Return the number of samples that should be allocated to a node
 * Guarantees best possible distribution of samples between nodes
 */
int samples_calc(int N, int rank, int nodes_total) {
    int samples_base = N / nodes_total;   
    int samples_remainder = N % nodes_total;

    samples_base = (rank < samples_remainder) ? ++samples_base : samples_base;

    return samples_base;
}
