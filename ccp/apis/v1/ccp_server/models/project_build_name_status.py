# coding: utf-8

from __future__ import absolute_import
from datetime import date, datetime  # noqa: F401

from typing import List, Dict  # noqa: F401

from ccp.apis.v1.ccp_server.models.base_model_ import Model
from ccp.apis.v1.ccp_server import util


class ProjectBuildNameStatus(Model):
    """NOTE: This class is auto generated by the swagger code generator program.

    Do not edit the class manually.
    """

    def __init__(self, build: str = None, status: str = None):  # noqa: E501
        """ProjectBuildNameStatus - a model defined in Swagger

        :param build: The build of this ProjectBuildNameStatus.  # noqa: E501
        :type build: str
        :param status: The status of this ProjectBuildNameStatus.  # noqa: E501
        :type status: str
        """
        self.swagger_types = {
            'build': str,
            'status': str
        }

        self.attribute_map = {
            'build': 'build',
            'status': 'status'
        }

        self._build = build
        self._status = status

    @classmethod
    def from_dict(cls, dikt) -> 'ProjectBuildNameStatus':
        """Returns the dict as a model

        :param dikt: A dict.
        :type: dict
        :return: The ProjectBuildNameStatus of this ProjectBuildNameStatus.  # noqa: E501
        :rtype: ProjectBuildNameStatus
        """
        return util.deserialize_model(dikt, cls)

    @property
    def build(self) -> str:
        """Gets the build of this ProjectBuildNameStatus.


        :return: The build of this ProjectBuildNameStatus.
        :rtype: str
        """
        return self._build

    @build.setter
    def build(self, build: str):
        """Sets the build of this ProjectBuildNameStatus.


        :param build: The build of this ProjectBuildNameStatus.
        :type build: str
        """

        self._build = build

    @property
    def status(self) -> str:
        """Gets the status of this ProjectBuildNameStatus.


        :return: The status of this ProjectBuildNameStatus.
        :rtype: str
        """
        return self._status

    @status.setter
    def status(self, status: str):
        """Sets the status of this ProjectBuildNameStatus.


        :param status: The status of this ProjectBuildNameStatus.
        :type status: str
        """

        self._status = status
