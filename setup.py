from setuptools import setup, find_packages
from os import path, environ
from io import open

here = path.abspath(path.dirname(__file__))

with open(path.join(here, 'README.md'), encoding='utf-8') as f:
    long_description = f.read()

setup(
    name='norecon',
    version=0.1,
    description='auto recon tools for domain, whois, service scan and screenshot.',
    author='ntestoc3',
    author_email='ntoooooon@outlook.com',
    url='https://github.com/',
    keywords='recon hacking domain scan whois',

    packages=["norecon"],
    package_data={
        'norecon' : ['*.hy'],
        'templates'
    },

    classifiers=[
        #   3 - Alpha
        #   4 - Beta
        #   5 - Production/Stable
        'Development Status :: 3 - Alpha',
        'Intended Audience :: Developers',
        'License :: OSI Approved :: MIT',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.6',
        'Programming Language :: Python :: 3.7',
        'Programming Language :: Python :: 3.8',
    ],
    python_requires='>=3.6, <4',
    install_requires=[
        'bs4',
        'fake-useragent',
        'hy',
        'requests',
        'retry',
        'lxml',
        'ratelimit',
        'publicsuffix2',
        'dnspython',
        'python-whois',
        'ipwhois',
        'validators',
        'event-bus',
        'qqwry-py3',
        'Jinja2',
    ],
)
