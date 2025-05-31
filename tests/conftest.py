import logging

from infrahouse_core.logging import setup_logging

# "303467602807" is our test account
TEST_ACCOUNT = "303467602807"
# TEST_ROLE_ARN = "arn:aws:iam::303467602807:role/jumphost-tester"
DEFAULT_PROGRESS_INTERVAL = 10
UBUNTU_CODENAME = "jammy"
TERRAFORM_ROOT_DIR = "test_data"

LOG = logging.getLogger(__name__)

setup_logging(LOG, debug=True)
