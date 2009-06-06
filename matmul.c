/******************************************************************************
* FILE: matmul.c
* DESCRIPTION:  
*   The master task distributes a matrix multiply operation to numtasks-1 worker tasks.
*   THe matrices are stored in row-major fashion
******************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <mpi.h>
#define MASTER 0        /* my_rank of first task */
#define FROM_MASTER 1       /* setting a message type */
#define FROM_WORKER 2       /* setting a message type */
#define DEBUG 0

MPI_Status status;
main(int argc, char **argv) 
{
    int numtasks,               /* number of tasks in partition */
        my_rank,                 /* a task identifier */
        numworkers,             /* number of worker tasks */
        source,                 /* task id of message source */
        dest,                   /* task id of message destination */
        nbytes,                 /* number of bytes in message */
        tag,                    /* message type */
        rows,                   /* rows of matrix A sent to each worker */
        averow, extra, offset,  /* used to determine rows sent to each worker */
        i, j, k,                /* misc */
        count,
        seed,
        NRA, NCA, NCB;

    if (argc != 4)              /*escape sequence for command line*/
    {
        printf("correct command is srun -N <no. of processors> <NRA> <NCA> <NCB>\n");
        return 0;
    }

    /*read inputs*/
    NRA = atoi(argv[1]);          /* number of rows in matrix A */
    NCA = atoi(argv[2]);          /* number of columns in matrix A */
    NCB = atoi(argv[3]);          /* number of columns in matrix B */

    #ifdef DEBUG 
    printf("NRA: %d NCA: %d NCB: %d\n", NRA, NCA, NCB);
    #endif
    
    double a[NRA][NCA],         /* matrix A to be multiplied */
           b[NCA][NCB],         /* matrix B to be multiplied */
           c[NRA][NCB];         /* result matrix C */

    double start,               /*start time*/
           end,                 /*end time*/
           time;                /*time elapsed*/
    
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &my_rank);
    MPI_Comm_size(MPI_COMM_WORLD, &numtasks);
    numworkers = numtasks-1;

    start=MPI_Wtime(); //record start time
/**************************** master side ************************************/
    if (my_rank == MASTER) 
    {
        #ifdef DEBUG 
        printf("Number of worker tasks = %d\n",numworkers);
        #endif
        
        for (i=0; i<NRA; i++) {
            for (j=0; j<NCA; j++)
            {   
                a[i][j]= (float) i;
                printf("%6.2f   ", a[i][j]);
            }
            printf("\n"); 
        }
        for (i=0; i<NCA; i++) {
            for (j=0; j<NCB; j++)
            {   
                b[i][j]= (float) j;
                printf("%6.2f   ", b[i][j]);
            }
            printf("\n"); 
        }

        /* send matrix data to the worker tasks */
        averow = NRA/numworkers;
        extra = NRA%numworkers;
        offset = 0;
        tag = FROM_MASTER;

        for (dest = 1; dest <= numworkers; dest++) {           
            rows = (dest <= extra) ? averow+1 : averow;     
            #ifdef DEBUG 
            printf("   SEND: rows: %d dest: %d a-offset: %d\n",rows,dest,offset);
            #endif

            MPI_Send(&offset, 1, MPI_INT, dest, tag, MPI_COMM_WORLD);
            MPI_Send(&rows, 1, MPI_INT, dest, tag, MPI_COMM_WORLD);

            count = rows * NCA;
            MPI_Send(&a[offset][0], count, MPI_DOUBLE, dest, tag, MPI_COMM_WORLD);

            count = NCA * NCB;
            MPI_Send(&b, count, MPI_DOUBLE, dest, tag, MPI_COMM_WORLD);

            offset = offset + rows;
        }

        /* wait for results from all worker tasks */
        tag = FROM_WORKER;
        for (i=1; i<=numworkers; i++)   
        {           
            source = i;
            MPI_Recv(&offset, 1, MPI_INT, source, tag, MPI_COMM_WORLD, &status);
            MPI_Recv(&rows, 1, MPI_INT, source, tag, MPI_COMM_WORLD, &status);
            count = rows*NCB;
            MPI_Recv(&c[offset][0], count, MPI_DOUBLE, source, tag, MPI_COMM_WORLD, 
                    &status);
         
        }

        /* print results */
        end = MPI_Wtime();
        time = end - start;

        printf("\n"); 
        printf("result:\n");
        for (i = 0; i < NRA; i++) { 
            for (j = 0; j < NCB; j++) {
                printf("%6.2f   ", c[i][j]);
            }
            printf("\n"); 
        }
        printf("\n"); 
        printf("time: %f\n",time);
    }  /* end of master section */



/**************************** worker task ************************************/
    if (my_rank > MASTER) 
    {
        tag = FROM_MASTER;
        source = MASTER;
        MPI_Recv(&offset, 1, MPI_INT, source, tag, MPI_COMM_WORLD, &status);
        MPI_Recv(&rows, 1, MPI_INT, source, tag, MPI_COMM_WORLD, &status);
        count = rows*NCA;
        MPI_Recv(&a, count, MPI_DOUBLE, source, tag, MPI_COMM_WORLD, &status);
        count = NCA*NCB;
        MPI_Recv(&b, count, MPI_DOUBLE, source, tag, MPI_COMM_WORLD, &status);

        #ifdef DEBUG 
        printf ("SLAVE(%d): source: %d tag: %d ", my_rank, source, tag);
        printf ("offset: %d ", offset);
        printf ("rows: %d ", rows);
        printf ("a[0][0]: %e ", a[0][0]);
        printf ("b[0][0]: %e ", b[0][0]);
        printf("\n"); 
        #endif

        int kmax, imax, jmax;
        kmax = NCB;
        imax = rows;
        jmax = NCA;

        #ifdef DEBUG 
        printf ("SLAVE(%d): kmax(NCB): %d imax(NRA): %d jmax(NCA): %d\n", my_rank, kmax, imax, jmax);
        #endif

        for (k=0; k<kmax; k++) {
            for (i=0; i<imax; i++) {
                c[i][k] = 0.0;
                for (j=0; j<jmax; j++) {
                    c[i][k] = c[i][k] + a[i][j] * b[j][k];
                }
            }
        }

        tag = FROM_WORKER;

        #ifdef DEBUG 
        printf ("COMPUTATION OK\n");
        #endif

        MPI_Send(&offset, 1, MPI_INT, MASTER, tag, MPI_COMM_WORLD);
        MPI_Send(&rows, 1, MPI_INT, MASTER, tag, MPI_COMM_WORLD);
        MPI_Send(&c, rows*NCB, MPI_DOUBLE, MASTER, tag, MPI_COMM_WORLD);

        #ifdef DEBUG 
        printf ("SEND OK\n");
        #endif
    }  /* end of worker */
    MPI_Finalize();
} /* of main */
