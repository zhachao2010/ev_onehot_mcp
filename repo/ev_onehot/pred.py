import os
import argparse
import numpy as np
import pandas as pd
from loguru import logger
from predictor import JointPredictor, EVPredictor, OnehotRidgePredictor
from util import spearman, ndcg, auroc


def load_predictor(data_path, model_dir=None, predictor_name='ev+onehot'):
    logger.info(f'Predictor {predictor_name} -----')
    predictor_cls = [EVPredictor, OnehotRidgePredictor]
    predictor = JointPredictor(data_path, predictor_cls, predictor_name)

    predictor.load_model(model_dir=model_dir)
    return predictor


def main(args):
    logger.info(f'Data path {args.data_path} -----')

    # Resolve model_dir (where ridge_model.joblib lives). Defaults to
    # data_path (legacy: model written alongside training data).
    model_dir = args.model_dir if args.model_dir is not None else args.data_path
    logger.info(f'Model path {model_dir} -----')

    # Resolve output_dir (where to write {seq_path}_pred.csv). Defaults to
    # the parent dir of seq_path (legacy: predictions next to the input csv).
    output_dir = args.output_dir
    if output_dir is not None:
        os.makedirs(output_dir, exist_ok=True)
        logger.info(f'Output path {output_dir} -----')

    # Load dataset
    seq_path = args.seq_path if args.seq_path is not None else f'{args.data_path}/data_test.csv'
    if os.path.exists(seq_path) and args.seq_path is not None:
        logger.info(f'Predicting sequences from {seq_path} -----')
        seq_df = pd.read_csv(seq_path)
    else:
        raise FileNotFoundError(f'Sequence file {seq_path} not found.')

    logger.info(f'Number of samples: {len(seq_df)}')

    predictor = load_predictor(args.data_path, model_dir=model_dir)
    test_pred = predictor.predict(seq_df[args.seq_col].values)

    if 'log_fitness' in seq_df.columns:
        metric_fns = {'spearman': spearman,}
        test_ret = [f"{m}: {mfn(test_pred, seq_df['log_fitness'].to_numpy())}" for m, mfn in metric_fns.items()]
        logger.info(", ".join(test_ret))

    seq_df['pred_fitness'] = test_pred

    # Compose output path: if --output-dir given, write there with the input
    # csv's basename + "_pred.csv"; otherwise legacy behaviour (sibling of input).
    if output_dir is not None:
        out_basename = os.path.basename(seq_path) + '_pred.csv'
        out_path = os.path.join(output_dir, out_basename)
    else:
        out_path = f'{seq_path}_pred.csv'
    seq_df.to_csv(out_path)
    logger.info(f'Predictions saved to {out_path}')


def parse_args():
    parser = argparse.ArgumentParser(description='Predict with ev+onehot model:'
                                                 'python pred.py <dataset_name> --seq_path <csv>')
    parser.add_argument('data_path', type=str,
                        help='Dataset path, including following files: \n'
                             'data_test.csv,    with  `seq` and `log_fitness` columns; \n'
                             'wt.fasta,         containing wild-type sequences;\n'
                             'plmc/,            folder contain EVmutation model parameters.\n'
                             '(ridge_model.joblib expected here too unless --model-dir is given)')
    parser.add_argument('--seq_path', dest='seq_path', type=str, default=None,
                        help='If provided, a csv file containing sequences to predict.')
    parser.add_argument('--seq_col', dest='seq_col', type=str, default='seq',
                        help='If provided, the column name in the csv file containing sequences to predict.')
    parser.add_argument('--ignore_gaps', dest='ignore_gaps', action='store_true')
    parser.add_argument('--model-dir', '--model_dir', dest='model_dir', type=str, default=None,
                        help='Directory containing ridge_model.joblib. Defaults to data_path (legacy).')
    parser.add_argument('--output-dir', '--output_dir', dest='output_dir', type=str, default=None,
                        help='Directory to write <basename(seq_path)>_pred.csv. Defaults to seq_path parent (legacy).')
    args = parser.parse_args()
    return args


if __name__ == '__main__':
    args = parse_args()
    main(args)
