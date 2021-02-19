from io import open
from os import environ, path

from setuptools import find_packages, setup

here = path.abspath(path.dirname(__file__))

with open(path.join(here, 'README.md'), encoding='utf-8') as f:
    long_description = f.read()

with open(path.join(here, "requirements.in"), encoding='utf-8') as f:
    requirements = f.read().splitlines()

setup(name='norecon',
      version=0.919,
      description='auto recon tools for domain, whois, service scan and screenshot.',
      author='ntestoc3',
      author_email='ntoooooon@outlook.com',
      url='https://github.com/ntestoc3/norecon',
      keywords='recon hacking domain scan whois',
      long_description=long_description,
      long_description_content_type="text/markdown",
      license="Expat",

      include_package_data=True,
      packages=["norecon"],
      package_data={
          'norecon': ['*'],
      },
      exclude_package_data={
          'norecon': ['*.log'],
      },

      entry_points={  # Optional
          'console_scripts': [
              'norecon=norecon.norecon:main',
              'domainvalid=norecon.domainvalid:main',
              'noamass=norecon.noamass:main',
              'nofindomain=norecon.nofindomain:main',
              'noffuf=norecon.noffuf:main',
              'nonmap=norecon.nonmap:main',
              'norecords=norecon.norecords:main',
              'noreport=norecon.noreport:main',
              'noresolvers=norecon.noresolvers:main',
              'noscreen=norecon.noscreen:main',
              'nosubsfinder=norecon.nosubsfinder:main',
              'nowhois=norecon.nowhois:main',
              'wildomains=norecon.wildomains:main',
              'nowx=norecon.nowx:main',
          ],
      },

      classifiers=[
          #   3 - Alpha
          #   4 - Beta
          #   5 - Production/Stable
          'Development Status :: 3 - Alpha',
          'Intended Audience :: Developers',
          'License :: OSI Approved :: MIT License',
          'Programming Language :: Python :: 3',
          'Programming Language :: Python :: 3.6',
          'Programming Language :: Python :: 3.7',
          'Programming Language :: Python :: 3.8',
      ],
      python_requires='>=3.6, <4',
      install_requires=requirements,
)
