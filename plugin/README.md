# 编译镜像
docker build -f plugin/Dockerfile -t ev_onehot .

# 如果国内环境，需手动下载依赖安装包到dependency，并编译Dockefile.cn

# 测试指令
docker run -it --rm  \
    -v $input_dir:/inputs \
    -v $output_dir:/outputs \
    ev_onehot:latest \
    python repo/ev_onehot/train.py /inputs --cross_val

docker run -it --rm  \
    -v $input_dir:/inputs \
    -v $output_dir:/outputs \
    ev_onehot:latest \
    python repo/ev_onehot/pred.py /inputs --seq_path /inputs/data.csv

# 检查结果
cd plugin/example/outputs
