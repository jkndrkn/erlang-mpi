/******************************************************************************
* FILE: mergesort.c
* DESCRIPTION:  
*   The master task distributes an array to the workers in chunks, zero pads for equal load balancing
*   The workers sort and return to the master, which does a final merge
******************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <mpi.h>



#define N 100000
#define MASTER 0		/* taskid of first task */

void showVector(int *v, int n, int id);
int * merge(int *A, int asize, int *B, int bsize);
void swap(int *v, int i, int j);
void m_sort(int *A, int min, int max);

double startT, stopT;

double startTime;

/*function to print a vector*/
void showVector(int *v, int n, int id)
{
	int i;
	printf("%d: ",id);
	for(i=0;i<n;i++)
		printf("%d ",v[i]);
	putchar('\n');
}

/*function to merge vectors*/
int * merge(int *A, int asize, int *B, int bsize) {
	int ai, bi, ci, i;
	int *C;
	int csize = asize+bsize;

	ai = 0;
	bi = 0;
	ci = 0;

	/* printf("asize=%d bsize=%d\n", asize, bsize); */

	C = (int *)malloc(csize*sizeof(int));	/*the array can be statically allocated too*/
	while ((ai < asize) && (bi < bsize)) {
		if (A[ai] <= B[bi]) {
			C[ci] = A[ai];
			ci++; ai++;
		} else {
			C[ci] = B[bi];
			ci++; bi++;
		}
	}

	if (ai >= asize)						/*if A is shorter*/
		for (i = ci; i < csize; i++, bi++)
			C[i] = B[bi];
	else if (bi >= bsize)					/*if B is shorter*/
		for (i = ci; i < csize; i++, ai++)
			C[i] = A[ai];

	for (i = 0; i < asize; i++)				
		A[i] = C[i];
	for (i = 0; i < bsize; i++)
		B[i] = C[asize+i];

	/* showVector(C, csize, 0); */
	return C;
}

void swap(int *v, int i, int j)
{
	int t;
	t = v[i];
	v[i] = v[j];
	v[j] = t;
}

void m_sort(int *A, int min, int max)
{
	int *C;		/* dummy, just to fit the function */
	int mid = (min+max)/2;
	int lowerCount = mid - min + 1;
	int upperCount = max - mid;

	/* If the range consists of a single element, it's already sorted */
	if (max == min) {
		return;
	} else {
		/* Otherwise, sort the first half */
		m_sort(A, min, mid);
		/* Now sort the second half */
		m_sort(A, mid+1, max);
		/* Now merge the two halves */
		C = merge(A + min, lowerCount, A + mid + 1, upperCount);
	}
}

main(int argc, char **argv)
{
	int * data;
	int * chunk;
	int * other;
	int m,n=N;
	int id,p;
	int s = 0;
	int i;
	int step;
	MPI_Status status;

	MPI_Init(&argc,&argv);
	MPI_Comm_rank(MPI_COMM_WORLD,&id);
	MPI_Comm_size(MPI_COMM_WORLD,&p);

	startT = MPI_Wtime();
	
/**************************** master task ************************************/
	if(id == MASTER)
	{
		int r;
		srandom(MPI_Wtime());
		s = n/p;
		r = n%p;
		data = (int *)malloc((n+s-r)*sizeof(int));
		for(i=0;i<n;i++)
			data[i] = random();
		if(r!=0)
		{
			for(i=n;i<n+s-r;i++)
				data[i]=0;
			s=s+1;
		}

		MPI_Bcast(&s,1,MPI_INT,0,MPI_COMM_WORLD);
		chunk = (int *)malloc(s*sizeof(int));
		MPI_Scatter(data,s,MPI_INT,chunk,s,MPI_INT,0,MPI_COMM_WORLD);
		m_sort(chunk, 0, s-1);
		/* showVector(chunk, s, id); */
	}

/**************************** worker task ************************************/
	else
	{
		MPI_Bcast(&s,1,MPI_INT,0,MPI_COMM_WORLD);
		chunk = (int *)malloc(s*sizeof(int));
		MPI_Scatter(data,s,MPI_INT,chunk,s,MPI_INT,0,MPI_COMM_WORLD);
		m_sort(chunk, 0, s-1);
		/* showVector(chunk, s, id);*/
	}



      /*data propagation in a tree fashion*/
	step = 1;
	while(step<p)
	{
		if(id%(2*step)==0)
		{
			if(id+step<p)
			{
				MPI_Recv(&m,1,MPI_INT,id+step,0,MPI_COMM_WORLD,&status);
				other = (int *)malloc(m*sizeof(int));
				MPI_Recv(other,m,MPI_INT,id+step,0,MPI_COMM_WORLD,&status);
				chunk = merge(chunk,s,other,m);
				s = s+m;
			} 
		}
		else
		{
			int near = id-step;
			MPI_Send(&s,1,MPI_INT,near,0,MPI_COMM_WORLD);
			MPI_Send(chunk,s,MPI_INT,near,0,MPI_COMM_WORLD);
			break;
		}
		step = step*2;
	}

	stopT = MPI_Wtime();
	if(id==0)
	{
		FILE * fout;

		printf("%d; %d processors; %f secs\n", s, p, (stopT-startT));

		fout = fopen("result","w");
		for(i=0;i<s;i++)
			fprintf(fout,"%d\n",chunk[i]);
		fclose(fout);
	}
	MPI_Finalize();
}
