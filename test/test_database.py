"""

"""

import os
import perturbation.base
import perturbation.database
import perturbation.models
import pytest
import sqlalchemy
import sqlalchemy.orm
import subprocess


@pytest.fixture
def session(output='/tmp/test.sqlite'):
    try:
        os.remove(output)
    except OSError:
        pass

    engine = sqlalchemy.create_engine('sqlite:///{}'.format(os.path.realpath(output)))

    session = sqlalchemy.orm.sessionmaker(bind=engine)

    perturbation.base.Base.metadata.create_all(engine)

    return session()


def test_seed(session):
    subprocess.run(['./munge.sh', 'test/data/set_1'])

    perturbation.database.seed('test/data/set_1', '/tmp/test.sqlite')

    n_plates = 1
    n_channels = 3
    n_patterns = 3
    n_wells = 2
    n_images = 4
    n_objects = 20
    n_bins_raddist = 4
    n_scales_texture = 3
    n_moments_coefs = 30

    n_matches = n_objects * n_patterns
    n_edges = n_matches * n_channels
    n_intensities = n_matches * n_channels
    n_textures = n_matches * n_channels * n_scales_texture
    n_radial_distributions = n_matches * n_channels * n_bins_raddist
    n_locations = n_matches * n_channels
    n_shapes = n_matches
    n_coordinates = n_matches + n_shapes + (n_matches * n_channels * 2)
    n_moments = n_shapes * n_moments_coefs
    n_neighborhoods = n_matches
    n_correlations = n_matches * 5

    assert len(session.query(perturbation.models.Pattern).all()) == n_patterns
    assert len(session.query(perturbation.models.Plate).all()) == n_plates
    assert len(session.query(perturbation.models.Channel).all()) == n_channels
    assert len(session.query(perturbation.models.Well).all()) == n_wells
    assert len(session.query(perturbation.models.Image).all()) == n_images
    assert len(session.query(perturbation.models.Match).all()) == n_matches
    assert len(session.query(perturbation.models.Edge).all()) == n_edges
    assert len(session.query(perturbation.models.Intensity).all()) == n_intensities
    assert len(session.query(perturbation.models.Texture).all()) == n_textures
    assert len(session.query(perturbation.models.RadialDistribution).all()) == n_radial_distributions
    assert len(session.query(perturbation.models.Shape).all()) == n_shapes
    assert len(session.query(perturbation.models.Location).all()) == n_locations
    assert len(session.query(perturbation.models.Coordinate).all()) == n_coordinates
    assert len(session.query(perturbation.models.Moment).all()) == n_moments
    assert len(session.query(perturbation.models.Neighborhood).all()) == n_neighborhoods
    assert len(session.query(perturbation.models.Correlation).all()) == n_correlations

    correlations = session.query(perturbation.models.Correlation)

    assert correlations.filter(perturbation.models.Correlation.match is None).all() == []


