# This class containes functions to generate layers

# Configuration

BASE_IMAGE ??= "aos-image-minimal"
PARENT_LAYER ??= "${BASE_IMAGE}"
LAYER_VERSION ??= "1"

# Inherit

inherit metadata-generator

# Dependencies

DEPENDS_append = " rsync-native"

# Variables

LAYER_DIGEST_TYPE = "sha256"
LAYER_MEDIA_TYPE = "application/vnd.aos.image.layer.v1.tar"

LAYER_WORK_DIR = "${WORKDIR}/layer"
LAYER_DEPLOY_DIR = "${DEPLOY_DIR_IMAGE}/layers"
PARENT_LAYER_ROOTFS = "${TMPDIR}/work-shared/${PARENT_LAYER}-${MACHINE}/rootfs"
ROOTFS_DIFF_DIR = "${WORKDIR}/rootfs_diff"
SHARED_DIGEST_DIR = "${TMPDIR}/work-shared/layers-${LAYER_DIGEST_TYPE}"

IMAGE_INSTALL_append = "${LAYER_FEATURES_${PN}}"

# Dirs

do_create_layer[cleandirs] += "${LAYER_WORK_DIR} ${ROOTFS_DIFF_DIR}"
do_create_layer[depends] += "${PARENT_LAYER}:do_create_shared_links"
do_create_layer[dirs] += "${SHARED_DIGEST_DIR} ${LAYER_DEPLOY_DIR} ${LAYER_WORK_DIR}"

# Disable unneeded tasks

do_image[noexec] = "1"
do_image_wic[noexec] = "1"
do_image_complete[noexec] = "1"

# Tasks

do_create_rootfs_archive() {
    rsync -HAXlrvcm --append --progress --delete --compare-dest=${PARENT_LAYER_ROOTFS}/ ${IMAGE_ROOTFS}/* ${ROOTFS_DIFF_DIR}
    find ${ROOTFS_DIFF_DIR} -type d -empty -delete

    # Create layer rootfs tar

    IMAGE_ROOTFS_TAR=${LAYER_WORK_DIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.tar

    ${IMAGE_CMD_TAR} --numeric-owner -cf ${IMAGE_ROOTFS_TAR} -C ${ROOTFS_DIFF_DIR} .

    # Create layer rootfs digest

    DIGEST="$(${LAYER_DIGEST_TYPE}sum -b ${IMAGE_ROOTFS_TAR} | cut -d' ' -f1)"
    echo "${DIGEST} ${LAYER_VERSION}" >  ${SHARED_DIGEST_DIR}/${PN}.${LAYER_DIGEST_TYPE}

    mv ${IMAGE_ROOTFS_TAR} ${LAYER_WORK_DIR}/${DIGEST}
}

python do_create_metadata() {
    import os
    
    # Plarform info

    platform_info = create_layer_platform_info(d.getVar("MACHINE_ARCH"), d.getVar("TARGET_OS"), d.getVar("DISTRO_VERSION"),
        d.getVar("LAYER_FEATURES_{}".format(d.getVar("PN"))).split())

    # Annotations

    parent_id = ""
    parent_digest = ""

    if d.getVar("PARENT_LAYER") != d.getVar("BASE_IMAGE"):
        f = open(os.path.join(d.getVar("SHARED_DIGEST_DIR"),
            "{}.{}".format(d.getVar("PARENT_LAYER"), d.getVar("LAYER_DIGEST_TYPE"))), "r")
        
        data = f.read().split()
        parent_id = "{}:{}".format(d.getVar("PARENT_LAYER"), data[1])
        parent_digest = "{}:{}".format(d.getVar("LAYER_DIGEST_TYPE"), data[0])

    annotations = create_layer_annotations("{}:{}".format(d.getVar("PN"), d.getVar("LAYER_VERSION")), parent_id, parent_digest)

    # Write metadata

    f = open(os.path.join(d.getVar("SHARED_DIGEST_DIR"),
        "{}.{}".format(d.getVar("PN"), d.getVar("LAYER_DIGEST_TYPE"))), "r")

    data = f.read().split()
    digest = "{}:{}".format(d.getVar("LAYER_DIGEST_TYPE"), data[0])

    write_layer_metadata(d.getVar("LAYER_WORK_DIR"), d.getVar("LAYER_MEDIA_TYPE"), digest,
        os.path.getsize(os.path.join(d.getVar("LAYER_WORK_DIR"), data[0])), platform_info, annotations)
}

do_pack_layer() {
    ${IMAGE_CMD_TAR} --numeric-owner -czf ${LAYER_DEPLOY_DIR}/${PN}-${MACHINE}-${LAYER_VERSION}.tar.gz -C ${LAYER_WORK_DIR} .
}

fakeroot python do_create_layer() {
    bb.build.exec_func("do_create_rootfs_archive", d)
    bb.build.exec_func("do_create_metadata", d)
    bb.build.exec_func("do_pack_layer", d)
}

addtask do_create_layer after do_rootfs before do_image_qa
