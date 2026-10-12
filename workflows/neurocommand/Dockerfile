# Build from the neuromono root. Both inputs must be Linux/amd64 digest-pinned
# references selected by the operator; see ../../WORKFLOWS.md.
ARG BASE_IMAGE
ARG APPTAINER_IMAGE
FROM ${APPTAINER_IMAGE} AS apptainer
FROM ${BASE_IMAGE}

USER root
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates coreutils curl git lmod python3 python3-venv \
    squashfs-tools squashfuse fuse-overlayfs libfuse3-3 libgomp1 \
    libglib2.0-0 libcairo2 which xz-utils \
    && rm -rf /var/lib/apt/lists/*
COPY --from=apptainer /opt/apptainer /opt/apptainer
RUN ln -s /opt/apptainer/bin/apptainer /usr/local/bin/apptainer \
    && ln -s /opt/apptainer/bin/singularity /usr/local/bin/singularity \
    && sed -i 's/^allow setuid = yes/allow setuid = no/' /opt/apptainer/etc/apptainer/apptainer.conf

# Prepare dependencies, never a published copy of the candidate source.
COPY neurocommand/neurodesk/requirements.txt /tmp/dependencies/neurodesk/requirements.txt
COPY neurocommand/test/requirements.txt /tmp/dependencies/test/requirements.txt
RUN python3 -m venv /opt/neurocommand-test \
    && /opt/neurocommand-test/bin/pip install --no-cache-dir -r /tmp/dependencies/test/requirements.txt \
    && rm -rf /tmp/dependencies \
    && mkdir -p /data /mnt /neurodesktop-storage /cvmfs
ENV PATH="/opt/neurocommand-test/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
RUN python3 -c 'import pytest, cairosvg, distutils.dir_util' \
    && bash -c 'source /usr/share/lmod/lmod/init/bash; module --version' \
    && singularity --version
WORKDIR /tmp
CMD ["/bin/bash"]
