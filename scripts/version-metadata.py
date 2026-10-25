#!/usr/bin/env python3
import datetime
import json
import re
import sys


def build_order(value):
    if not re.fullmatch(r'[0-9]{8}\.[1-9][0-9]*', value):
        raise ValueError('Build must use YYYYMMDD.N with a positive sequence number')
    day, sequence = value.split('.')
    datetime.datetime.strptime(day, '%Y%m%d')
    return int(day), int(sequence)


def release_metadata(version, build, channel='stable'):
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version):
        raise ValueError('Version must use X.Y.Z')
    build_order(build)
    if channel not in {'stable', 'beta'}:
        raise ValueError('Channel must be stable or beta')
    suffix = '' if channel == 'stable' else '-beta'
    tag = version if channel == 'stable' else f'{version}-beta-{build}'
    return {'version': version, 'build': build, 'channel': channel, 'tag': tag,
            'archive': f'Pir.Versions.{version}{suffix}-{build}.zip'}


if __name__ == '__main__':
    try:
        print(json.dumps(release_metadata(*sys.argv[1:])))
    except (TypeError, ValueError) as error:
        raise SystemExit(str(error))
