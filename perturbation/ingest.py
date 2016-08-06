import click
import configparser
import hashlib
import logging
import logging.config
import odo
import os
import perturbation.utils
import pkg_resources
import platform
import subprocess
import tempfile


logger = logging.getLogger(__name__)


def preprocess_csv(input, output, table_name, table_number):
    with tempfile.NamedTemporaryFile() as temp_file:

        nrows = sum(1 for line in open(input)) - 1

        cmd = "echo 'TableNumber' >> {}".format(temp_file.name)

        subprocess.check_output(cmd, shell=True)

        tmpl = "{}\\n%.0s".format(table_number)

        cmd = "printf '{0}' {{1..{1}}} >> {2}".format(tmpl, nrows, temp_file.name)

        subprocess.check_output(cmd, shell=True)

        cmd = "paste -d',' {} {} > {}".format(temp_file.name, input, output)

        subprocess.check_output(cmd, shell=True)

        sed_cmd = "gsed" if platform.system() == "Darwin" else "sed"

        cmd = "{sed} -r -i '1{{s/^/{pattern}_/g;s/,/,{pattern}_/g;s/{pattern}_ImageNumber/ImageNumber/1;s/{pattern}_ObjectNumber/ObjectNumber/1;s/{pattern}_TableNumber/TableNumber/1}}' {filename}".format(filename=output, pattern=table_name, sed=sed_cmd)

        subprocess.check_output(cmd, shell=True)


def into(csv_filename, output, table_name, table_number):

    with tempfile.TemporaryDirectory() as temp_dir:
        processed_csv_filename = os.path.join(temp_dir, os.path.basename(csv_filename))

        preprocess_csv(csv_filename, processed_csv_filename, table_name=table_name, table_number=table_number)

        odo.odo(processed_csv_filename, "{}::{}".format(output, table_name), has_header=True, delimiter=",")


def seed(config, input, output):
    """Call functions to create backend

    :param config
    :param input
    :param output
    :return: None
    """

    pathnames = perturbation.utils.find_directories(input)

    for directory in pathnames:
        try:
            pattern_csvs, image_csv = perturbation.utils.validate_csvs(config, directory)

        except OSError as e:
            logger.warning(e)

            continue

        logger.debug('Parsing {}'.format(directory))

        table_number = hashlib.md5(open(image_csv, 'rb').read()).hexdigest()

        image_table_name = config["filenames"]["image"].split(".")[0]

        into(csv_filename=image_csv, output=output, table_name=image_table_name, table_number=table_number)

        for pattern_csv in pattern_csvs:

                pattern = os.path.basename(pattern_csv).split('.')[0]

                into(csv_filename=pattern_csv, output=output, table_name=pattern, table_number=table_number)


config_file_sys = pkg_resources.resource_filename(pkg_resources.Requirement.parse("perturbation"), "config.ini")

@click.command()
@click.argument('input', type=click.Path(dir_okay=True, exists=True, readable=True))
@click.help_option(help='')
@click.option('-c', '--configfile', default=config_file_sys, type=click.Path(exists=True, file_okay=True, readable=True))
@click.option('-d', '--skipmunge', default=False, is_flag=True)
@click.option('-o', '--output', type=click.Path(exists=False, file_okay=True, writable=True))
@click.option('-v', '--verbose', default=False, is_flag=True)
def main(configfile, input, output, verbose, skipmunge):
    """

    :param configfile:
    :param input:
    :param output:
    :param skipmunge:
    :param verbose:

    :return:

    """

    import json

    with open(pkg_resources.resource_filename(pkg_resources.Requirement.parse("perturbation"), "logging_config.json")) as f:
        logging.config.dictConfig(json.load(f))

    logger = logging.getLogger(__name__)

    config = configparser.ConfigParser()

    config.read(configfile)

    if not skipmunge:
        logger.debug('Calling munge')
        subprocess.call([pkg_resources.resource_filename(pkg_resources.Requirement.parse("perturbation"), "munge.sh"), input])
        logger.debug('Completed munge')
    else:
        logger.debug('Skipping munge')

    perturbation.ingest.seed(config=config, input=input, output=output)

    logger.debug('Finish')



