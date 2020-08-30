#!/usr/bin/env sh

rm -rf dist/
python setup.py clean --all
python setup.py sdist bdist_wheel
pip uninstall -y norecon
pip install dist/*.whl
