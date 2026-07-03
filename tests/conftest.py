import logging

from infrahouse_core.logging import setup_logging
from pytest_infrahouse import LOG as IH_LOG

TERRAFORM_ROOT_DIR = "test_data"

LOG = logging.getLogger(__name__)

setup_logging(LOG, debug=True)
setup_logging(IH_LOG, debug=True)
