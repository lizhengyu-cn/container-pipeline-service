from tests.test_00_unit.test_04_index_ci.indexcibase import IndexCIBase, \
    DUMMY_INDEX_FILE
from ci.container_index.lib.constants import *
import ci.container_index.lib.checks.schema_validation as schema_validation


class IDValidationTests(IndexCIBase):

    def test_00_setup_test(self):
        self._setup_test()

    def test_01_validation_succeeds_valid_id(self):
        self.assertTrue(
            schema_validation.IDValidator(
                {
                    FieldKeys.ID: 1
                },
                DUMMY_INDEX_FILE
            ).validate().success
        )

    def test_02_validation_fails_missing_id(self):
        self.assertFalse(
            schema_validation.IDValidator(
                {
                    "ID": 1
                },
                DUMMY_INDEX_FILE
            ).validate().success
        )

    def test_03_validation_fails_id_not_number(self):
        self.assertFalse(
            schema_validation.IDValidator(
                {
                    FieldKeys.ID: "1"
                },
                DUMMY_INDEX_FILE
            ).validate().success
        )
