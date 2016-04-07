import collections
import glob
import hashlib
import logging
import os

import click
import pandas
import sqlalchemy
import sqlalchemy.orm

import perturbation.base
import perturbation.migration
import perturbation.models

create_center = perturbation.migration.create_center

create_center_mass_intensity = perturbation.migration.create_center_mass_intensity

create_channel = perturbation.migration.create_channel

create_correlation = perturbation.migration.create_correlation

create_edge = perturbation.migration.create_edge

create_image = perturbation.migration.create_image

create_intensity = perturbation.migration.create_intensity

create_location = perturbation.migration.create_location

create_match = perturbation.migration.create_match

create_max_intensity = perturbation.migration.create_max_intensity

create_moment = perturbation.migration.create_moment

create_neighborhood = perturbation.migration.create_neighborhood

create_object = perturbation.migration.create_object

create_plate = perturbation.migration.create_plate

create_quality = perturbation.migration.create_quality

create_radial_distribution = perturbation.migration.create_radial_distribution

create_shape = perturbation.migration.create_shape

create_shape_center = perturbation.migration.create_shape_center

create_texture = perturbation.migration.create_texture

create_well = perturbation.migration.create_well

find_image_by = perturbation.migration.find_image_by

find_object_by = perturbation.migration.find_object_by

find_plate_by = perturbation.migration.find_plate_by


logger = logging.getLogger(__name__)


Base = perturbation.base.Base

Session = sqlalchemy.orm.sessionmaker()

engine = None

scoped_session = sqlalchemy.orm.scoped_session(Session)


cdef int correlation_offset = 0
cdef int intensity_offset = 0
cdef int location_offset = 0
cdef int moment_offset = 0
cdef int texture_offset = 0
cdef int radial_distribution_offset = 0


cdef list channels = []
cdef list coordinates = []
cdef list correlations = []
cdef list edges = []
cdef list images = []
cdef list intensities = []
cdef list locations = []
cdef list qualities = []
cdef list matches = []
cdef list neighborhoods = []
cdef list plates = []
cdef list radial_distributions = []
cdef list shapes = []
cdef list textures = []
cdef list wells = []


def find_directories(directory):
    directories = []

    filenames = glob.glob(os.path.join(directory, '*'))

    for filename in filenames:
        directories.append(os.path.relpath(filename))

    return set(directories)


def setup(database):
    global engine

    engine = sqlalchemy.create_engine('sqlite:///{}'.format(os.path.realpath(database)))

    scoped_session.remove()

    scoped_session.configure(autoflush=False, bind=engine, expire_on_commit=False)

    Base.metadata.drop_all(engine)

    Base.metadata.create_all(engine)


def seed(input, output, sqlfile, verbose=False):
    setup(output)

    create_views(sqlfile)

    seed_plate(input)


def create_views(sqlfile):
    logger.debug('Parsing SQL file')

    with open(sqlfile) as f:
        import sqlparse

        for s in sqlparse.split(f.read()):
            engine.execute(s)


def seed_plate(directories):
    for directory in find_directories(directories):
        try:
            data = pandas.read_csv(os.path.join(directory, 'image.csv'))
        except OSError:
            continue

        logger.debug('Parsing {}'.format(os.path.basename(directory)))

        moments_group = []

        digest = hashlib.md5(open(os.path.join(directory, 'image.csv'), 'rb').read()).hexdigest()

        plate_descriptions = data['Metadata_Barcode'].unique()

        logger.debug('\tParse plates, wells, images, quality')

        create_plates(data, digest, images, plate_descriptions, plates, qualities, wells)

        logger.debug('\tParse objects')

        # TODO: Read all the patterns because some columns are present in only one pattern
        data = pandas.read_csv(os.path.join(directory, 'Cells.csv'))

        def get_object_numbers(s):
            return data[['ImageNumber', s]].rename(columns={s: 'ObjectNumber'}).drop_duplicates()

        object_numbers = pandas.concat([get_object_numbers(s) for s in ['ObjectNumber', 'Neighbors_FirstClosestObjectNumber_5', 'Neighbors_SecondClosestObjectNumber_5']])

        object_numbers.drop_duplicates()

        objects = find_objects(digest, images, object_numbers)

        logger.debug('\tParse feature parameters')

        filenames = []

        for filename in glob.glob(os.path.join(directory, '*.csv')):
            if filename not in [os.path.join(directory, 'image.csv'), os.path.join(directory, 'object.csv')]:
                filenames.append(os.path.basename(filename))

        pattern_descriptions = find_pattern_descriptions(filenames)

        patterns = find_patterns(pattern_descriptions, scoped_session)

        columns = data.columns

        find_channel_descriptions(channels, columns)

        correlation_columns = find_correlation_columns(channels, columns)

        scales = find_scales(columns)

        counts = find_counts(columns)

        moments = find_moments(columns)

        create_patterns(channels, coordinates, correlation_columns, correlation_offset, correlations, counts, digest, directory, edges, images, intensities, intensity_offset, location_offset, locations, matches, moment_offset, moments, moments_group, neighborhoods, objects, patterns, qualities, radial_distribution_offset, radial_distributions, scales, shapes, texture_offset, textures, wells)

    perturbation.migration.save_channels(channels)

    perturbation.migration.save_plates(plates)

    logger.debug('Commit plate, channel')


def find_objects(digest, images, object_numbers):
    objects = []

    for index, object_number in object_numbers.iterrows():
        object_dictionary = create_object(digest, images, object_number)

        objects.append(object_dictionary)

    return objects


def create_patterns(channels, coordinates, correlation_columns, correlation_offset, correlations, counts, digest, directory, edges, images, intensities, intensity_offset, location_offset, locations, matches, moment_offset, moments, moments_group, neighborhoods, objects, patterns, qualities, radial_distribution_offset, radial_distributions, scales, shapes, texture_offset, textures, wells):
    for pattern in patterns:
        logger.debug('\tParse {}'.format(pattern.description))

        data = pandas.read_csv(os.path.join(directory, '{}.csv').format(pattern.description))

        with click.progressbar(length=data.shape[0], label="Processing " + pattern.description, show_eta=True) as bar:
            for index, row in data.iterrows():
                bar.update(1)

                row = collections.defaultdict(lambda: None, row)

                image_id = find_image_by(description='{}_{}'.format(digest, int(row['ImageNumber'])), dictionaries=images)

                object_id = find_object_by(description=str(int(row['ObjectNumber'])), image_id=image_id, dictionaries=objects)

                center = create_center(row)

                coordinates.append(center)

                neighborhood = create_neighborhood(object_id, row)

                if row['Neighbors_FirstClosestObjectNumber_5']:
                    description = str(int(row['Neighbors_FirstClosestObjectNumber_5']))

                    closest_id = find_object_by(description=description, image_id=image_id, dictionaries=objects)

                    neighborhood._replace(closest_id=closest_id)

                if row['Neighbors_SecondClosestObjectNumber_5']:
                    description = str(int(row['Neighbors_SecondClosestObjectNumber_5']))

                    second_closest_id = find_object_by(description=description, image_id=image_id, dictionaries=objects)

                    neighborhood._replace(second_closest_id=second_closest_id)

                neighborhoods.append(neighborhood)

                shape_center = create_shape_center(row)

                coordinates.append(shape_center)

                shape = create_shape(row, shape_center)

                shapes.append(shape)

                create_moments(moments, moments_group, row, shape)

                match = create_match(center, neighborhood, object_id, pattern, shape)

                matches.append(match)

                create_correlations(correlation_columns, correlations, match, row)

                create_channels(channels, coordinates, counts, edges, intensities, locations, match, radial_distributions, row, scales, textures)

    perturbation.migration.save_coordinates(coordinates)
    perturbation.migration.save_edges(edges)
    perturbation.migration.save_images(images)
    perturbation.migration.save_matches(matches)
    perturbation.migration.save_neighborhoods(neighborhoods)
    perturbation.migration.save_objects(objects)
    perturbation.migration.save_qualities(qualities)
    perturbation.migration.save_shapes(shapes)
    perturbation.migration.save_textures(texture_offset, textures)
    perturbation.migration.save_wells(wells)
    perturbation.migration.save_correlations(correlation_offset, correlations)
    perturbation.migration.save_intensities(intensities, intensity_offset)
    perturbation.migration.save_locations(location_offset, locations)
    perturbation.migration.save_moments(moment_offset, moments, moments_group)
    perturbation.migration.save_radial_distributions(radial_distribution_offset, radial_distributions)

    logger.debug('\tCommit {}'.format(os.path.basename(directory)))


def find_pattern_descriptions(filenames):
    pattern_descriptions = []

    for filename in filenames:
        pattern_descriptions.append(filename.split('.')[0])

    return pattern_descriptions


def find_patterns(pattern_descriptions, session):
    patterns = []

    for pattern_description in pattern_descriptions:
        pattern = perturbation.models.Pattern.find_or_create_by(session=session, description=pattern_description)

        patterns.append(pattern)

    return patterns


def find_channel_descriptions(channels, columns):
    channel_descriptions = []

    for column in columns:
        split_columns = column.split('_')

        if split_columns[0] == 'Intensity':
            channel_descriptions.append(split_columns[2])

    channel_descriptions = set(channel_descriptions)

    for channel_description in channel_descriptions:
        channel = perturbation.migration.find_channel_by(channels, channel_description)

        if not channel:
            channel = create_channel(channel_description, channel)

            channels.append(channel)


def find_moments(columns):
    moments = []

    for column in columns:
        split_columns = column.split('_')

        if split_columns[0] == 'AreaShape' and split_columns[1] == 'Zernike':
            moments.append((split_columns[2], split_columns[3]))

    return moments


def find_counts(columns):
    counts = []

    for column in columns:
        split_columns = column.split('_')

        if split_columns[0] == 'RadialDistribution':
            counts.append(split_columns[3].split('of')[0])

    counts = set(counts)

    return counts


def find_scales(columns):
    scales = []

    for column in columns:
        split_columns = column.split('_')

        if split_columns[0] == 'Texture':
            scales.append(split_columns[3])

    scales = set(scales)

    return scales


def find_correlation_columns(channels, columns):
    correlation_columns = []

    for column in columns:
        split_columns = column.split('_')

        a = None
        b = None

        if split_columns[0] == 'Correlation':
            for channel in channels:
                if channel.description == split_columns[2]:
                    a = channel

                if channel.description == split_columns[3]:
                    b = channel

            correlation_columns.append((a, b))

    return correlation_columns


def create_correlations(correlation_columns, correlations, match, row):
    for dependent, independent in correlation_columns:
        correlation = create_correlation(dependent, independent, match, row)

        correlations.append(correlation)


def create_moments(moments, moments_group, row, shape):
    for a, b in moments:
        moment = create_moment(a, b, row, shape)

        moments_group.append(moment)


def create_channels(channels, coordinates, counts, edges, intensities, locations, match, radial_distributions, row, scales, textures):
    for channel in channels:
        intensity = create_intensity(channel, match, row)

        intensities.append(intensity)

        edge = create_edge(channel, match, row)

        edges.append(edge)

        center_mass_intensity = create_center_mass_intensity(channel, row)

        coordinates.append(center_mass_intensity)

        max_intensity = create_max_intensity(channel, row)

        coordinates.append(max_intensity)

        location = create_location(center_mass_intensity, channel, match, max_intensity)

        locations.append(location)

        create_textures(channel, match, row, scales, textures)

        create_radial_distributions(channel, counts, match, radial_distributions, row)


def create_radial_distributions(channel, counts, match, radial_distributions, row):
    for count in counts:
        radial_distribution = create_radial_distribution(channel, count, match, row)

        radial_distributions.append(radial_distribution)


def create_textures(channel, match, row, scales, textures):
    for scale in scales:
        texture = create_texture(channel, match, row, scale)

        textures.append(texture)


def create_images(data, digest, descriptions, images, qualities, well):
    for description in descriptions:
        image = create_image(digest, description, well)

        images.append(image)

        quality = create_quality(data, description, image)

        qualities.append(quality)


def create_plates(data, digest, images, descriptions, plates, qualities, wells):
    for description in descriptions:
        plate = find_plate_by(plates, str(int(description)))

        if not plate:
            plate = create_plate(description, plate)

            plates.append(plate)

        well_descriptions = data[data['Metadata_Barcode'] == description]['Metadata_Well'].unique()

        create_wells(data, digest, images, plate, description, qualities, well_descriptions, wells)


def create_wells(data, digest, images, plate, plate_description, qualities, descriptions, wells):
    for description in descriptions:
        well = create_well(plate, description)

        wells.append(well)

        image_descriptions = data[(data['Metadata_Barcode'] == plate_description) & (data['Metadata_Well'] == description)]['ImageNumber'].unique()

        create_images(data, digest, image_descriptions, images, qualities, well)
