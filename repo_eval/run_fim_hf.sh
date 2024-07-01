#!/usr/bin/env bash

export PYTHONIOENCODING=utf-8

export model=${1:-"starcoderbase-1b"}
export exp=${2:-"baseline"}  # baseline, rg1, oracle, lrcontext, rcfcl_rg1
export ranker=${3:-"sparse"} # sparse, unixcoder

HOME_DIR=`realpath ..`

data_root=`realpath ./processed_data`

mkdir -p ${HOME_DIR}/results/repoeval
output_root=`realpath ${HOME_DIR}/results/repoeval`


# You may use other non-fim models. To do so, simply provide the model name and remove the "--use_fim_prompt" flag.
# Also, specify the batch size and dtype.
declare -A py_model_zoo
py_model_zoo["starcoder"]="bigcode/starcoder"
py_model_zoo["starcoderbase"]="bigcode/starcoderbase"
py_model_zoo["starcoderbase-7b"]="bigcode/starcoderbase-7b"
py_model_zoo["starcoderbase-3b"]="bigcode/starcoderbase-3b"
py_model_zoo["starcoderbase-1b"]="bigcode/starcoderbase-1b"

declare -A batch_size
batch_size["starcoder"]=1
batch_size["starcoderbase"]=1
batch_size["starcoderbase-7b"]=2
batch_size["starcoderbase-3b"]=8
batch_size["starcoderbase-1b"]=16

# helpful command if we terminate jobs
# nvidia-smi | grep 'python' | awk '{ print $5 }' | xargs -n1 sudo kill -9
# ps -fA | grep python3 | awk '{ print $2 }' | xargs -n1 sudo kill -9

model_name=${py_model_zoo["$model"]}
model_type=codelm
if [[ $exp == "rg1" || $exp == "oracle" ]]; then
    model_type=codelm_cfc
elif [[ $exp == "lrcontext" ]]; then
    model_type=codelm_leftright_context
elif [[ $exp == "rcfcl_rg1" || $exp == "rcfcl_oracle" ]]; then
    model_type=codelm_right_cfc_left
fi

max_seq_length=2048
dtype=bf16

function run() {
    task=$1

    if [[ $exp == "baseline" || $exp == "lrcontext" ]]; then
        prompt_file="$data_root/python_${task}.jsonl"
        output_dir=$output_root/$exp/$task
    elif [[ $exp == "rcfcl_rg1" ]]; then
        prompt_file="$data_root/python_${task}_${ranker}_rg1.jsonl"
        output_dir=$output_root/$exp/$ranker/$task
    elif [[ $exp == "rcfcl_oracle" ]]; then
        prompt_file="$data_root/python_${task}_${ranker}_oracle.jsonl"
        output_dir=$output_root/$exp/$ranker/$task
    else
        prompt_file="$data_root/$setting/python_${task}_${ranker}_${exp}.jsonl"
        output_dir=$output_root/$setting/$exp/$ranker/$task
    fi

    out_dirname=$(echo $model_name | tr '[:upper:]' '[:lower:]' | tr '/-' '_')
    output_dir=$output_dir/$out_dirname
    mkdir -p $output_dir

    gen_length=50
    if [[ $task == "function_completion" ]]; then
        gen_length=256
    fi

    accelerate launch --main_process_port 29512 eval_hf.py \
        --task $task \
        --model_type $model_type \
        --model_name_or_path $model_name \
        --use_fim_prompt \
        --cfc_seq_length 512 \
        --min_cfc_score 0.0 \
        --prompt_file $prompt_file \
        --gen_length $gen_length \
        --max_seq_length $max_seq_length \
        --preprocessing_num_workers 1 \
        --batch_size ${batch_size["$model"]} \
        --output_dir $output_dir \
        --dtype $dtype \
        --ts_lib ${HOME_DIR}/build/python-lang-parser.so \
        --language python 2>&1 | tee $output_dir/log.txt
}

run line_completion
run api_completion
run function_completion
