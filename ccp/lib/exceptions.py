"""
This script defines custom exceptions of the service.
"""


class InvalidPipelineName(Exception):
    """
    Exception to be raised when pipeline name populated doesn't
    confornt to allowed value for openshift template field metadata.name
    """
    pass


class CommandOutputError(Exception):
    """
    Exception to be raised when running a command does not fail but command
    gives an error message.
    """
    pass


class TemplateDoesNotExistError(Exception):
    """
    Exception to be raised when a template file does not exist
    """
    pass


class ErrorAccessingIndexEntryAttributes(Exception):
    """
    Exception to be raised when there are errors accessing
    index entry attributes
    """
    pass


class InformationNotInJenkinsError(Exception):
    """
    Exception to be raised when jenkins is unable to provide requested
    information
    """
    pass
