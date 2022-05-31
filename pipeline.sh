#!/bin/bash

usage() {
  echo "Usage: $0 [-l RM_LIBRARY] [-g GENOME] [-T THREADS]" 1>&2; exit 1;
}

exit_abnormal() {
  usage
  exit 1
}

while getopts 'l:g:T:' flag; do
  case "${flag}" in
    l)
      RM_LIBRARY=${OPTARG}
      ;;
    g)
      GENOME=${OPTARG}
      ;;
    T)
      THREADS=${OPTARG}
      if ! [[ "$THREADS" =~ ^[0-9]+$ ]] ; then
        echo "Error: THREADS must be a positive, whole number."
        exit_abnormal
        exit 1
      elif [ "$THREADS" -eq 0 ]; then
        echo "Error: THREADS must be a positive, whole number."
        exit_abnormal
      fi
      ;;
    *) 
       exit_abnormal
       ;;
  esac
done

if ! [ -f "${RM_LIBRARY}" ] ; then
  echo "Error: RM_LIBRARY not found."
  usage
  exit 1
fi

if ! [ -f "${GENOME}" ] ; then
  echo "Error: GENOME not found."
  usage
  exit 1
fi

GENOME_NAME=$( echo $GENOME | sed 's/.*\///' )
RM_LIBRARY_NAME=$( echo $GENOME | sed 's/.*\///' )

mkdir -p data/split out/initial_search/ out/self_search/ out/to_align/ out/mafft/

export GENOME
export THREADS

cd-hit-est -n 10 -c 0.95 -i ${RM_LIBRARY} -o data/clustered_${RM_LIBRARY_NAME} # cluster seq

Rscript splitter.R -t nt -f data/clustered_${RM_LIBRARY_NAME} -o data/split/ -p 128 # split query

ls data/split/clustered_${RM_LIBRARY_NAME}.* | sed 's/.*\///' > data/queries.txt # list queries

if [ ! -f "${GENOME}".nsq ]; then
  makeblastdb -in ${GENOME} -dbtype nucl -out ${GENOME} # makeblastb if needed
fi

parallel --env GENOME_NAME --bar --jobs ${THREADS} -a data/queries.txt blastn -task dc-megablast -query data/split/{} -db $GENOME -evalue 1e-5 -outfmt \"6 qseqid sseqid pident length qstart qend qlen sstart send slen evalue bitscore\" -out out/initial_search/{}.out -num_threads 1 # search genome
 
cat out/initial_search/clustered_${RM_LIBRARY_NAME}_seq_*.fasta.out > out/${GENOME_NAME}_initial_search.out # compile data

Rscript self_blast_setup.R -g ${GENOME} -l ${RM_LIBRARY} # extend seqs

ls out/initial_seq/${GENOME_NAME}*.fasta | sed 's/.*\///' > out/${GENOME_NAME}_self_queries.txt

parallel --env GENOME_NAME --bar --jobs ${THREADS} -a out/${GENOME_NAME}"_self_queries.txt" blastn -task dc-megablast -query out/initial_seq/{} -subject out/initial_seq/{} -evalue 1e-5 -outfmt \"6 qseqid sseqid pident length qstart qend qlen sstart send slen evalue bitscore\" -out out/self_search/{}.out -num_threads 1 # self blast

Rscript mafft_setup.R -g ${GENOME_NAME} # trim seqs pre-mafft

parallel --env GENOME_NAME --bar --jobs 1 -a out/${GENOME_NAME}"_to_align.txt" echo "mafft --thread $THREADS --localpair --adjustdirectionaccurately out/to_align/{} out/mafft/{}"

parallel --env GENOME_NAME --bar --jobs ${THREADS} -a out/${GENOME_NAME}"_to_align.txt" CIAlign --infile out/mafft/{} --outfile_stem out/CIAlign/{} --crop_ends --make_consensus --consensus_name {}

Rscript compiler.R -g ${GENOME}

Rscript splitter.R -t nt -f out/needs_rewash_${GENOME_NAME} -o data/split/ -p 128 # split query

ls data/split/needs_rewash_${GENOME_NAME}* | sed 's/.*\///' > data/rewash_queries_${GENOME_NAME}.txt # list queries

parallel --env GENOME_NAME --bar --jobs ${THREADS} -a data/"rewash_queries_"${GENOME_NAME}".txt" blastn -task dc-megablast -query data/split/{} -db $GENOME -evalue 1e-5 -outfmt \"6 qseqid sseqid pident length qstart qend qlen sstart send slen evalue bitscore\" -out out/initial_search/{}.out -num_threads 1 # search genome
 
cat out/initial_search/needs_rewash_${GENOME_NAME}_seq_*.fasta.out > out/${GENOME_NAME}_rewash_search.out # compile data

Rscript rewash_self_blast_setup.R -g ${GENOME} -l out/needs_rewash_${GENOME_NAME} # extend seqs

ls out/initial_seq/rewash_${GENOME_NAME}*.fasta | sed 's/.*\///' > out/rewash_${GENOME_NAME}_self_queries.txt

parallel --env GENOME_NAME --bar --jobs ${THREADS} -a out/rewash_${GENOME_NAME}"_self_queries.txt" blastn -task dc-megablast -query out/initial_seq/{} -subject out/initial_seq/{} -evalue 1e-5 -outfmt \"6 qseqid sseqid pident length qstart qend qlen sstart send slen evalue bitscore\" -out out/self_search/{}.out -num_threads 1 # self blast

Rscript rewash_mafft_setup.R -g ${GENOME_NAME} # trim seqs pre-mafft

parallel --env GENOME_NAME --bar --jobs 1 -a out/${GENOME_NAME}"_to_rewash_align.txt" "mafft --thread $THREADS --localpair --adjustdirectionaccurately out/to_align/{} > out/mafft/{}" # align

parallel --env GENOME_NAME --bar --jobs ${THREADS} -a out/${GENOME_NAME}"_to_rewash_align.txt" CIAlign --infile out/mafft/{} --outfile_stem out/CIAlign/{} --crop_ends --make_consensus --consensus_name {} #trim and consensus

Rscript final_spin.R -g ${GENOME} -l ${RM_LIBRARY} # compile all together