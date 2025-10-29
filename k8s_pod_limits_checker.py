#!/usr/bin/env python3.13
"""
Kubernetes Pod Resource Limits Checker

This script identifies containers across all namespaces that are missing
CPU and/or memory resource limits. Optionally, it can automatically annotate
pods with warning labels.

For usage instructions and examples, see the README.md file.
"""

import sys
import json
import argparse
import logging
import os
from pathlib import Path
from typing import List, Dict, Tuple, Optional
from dataclasses import dataclass, asdict

try:
    from kubernetes import client, config
    from kubernetes.client.rest import ApiException
except ImportError:
    print("Error: kubernetes package not found.")
    print("If using uv: Run 'uv run k8s_pod_limits_checker.py' and uv will install dependencies automatically.")
    print("If not using uv: Install with 'pip install kubernetes'")
    sys.exit(1)


@dataclass
class ContainerLimitIssue:
    """Represents a container with missing resource limits."""
    namespace: str
    pod_name: str
    container_name: str
    missing_cpu_limit: bool
    missing_memory_limit: bool


class KubernetesPodChecker:
    """Handles interaction with Kubernetes API to check pod resource limits."""

    def __init__(self, logger: logging.Logger):
        """
        Initialize the Kubernetes pod checker.

        Args:
            logger: Logger instance for logging operations
        """
        self.logger = logger
        self.v1_client = None

    def connect(self) -> bool:
        """
        Connect to the Kubernetes cluster using in-cluster config or kubeconfig.
        Tries in-cluster config first (for pods), then falls back to kubeconfig (for local dev).

        Returns:
            bool: True if connection successful, False otherwise
        """
        try:
            # Try in-cluster config first (when running inside a pod)
            config.load_incluster_config()
            self.v1_client = client.CoreV1Api()
            self.logger.info("Successfully connected to Kubernetes cluster using in-cluster config")
            return True
        except config.ConfigException:
            # Fall back to kubeconfig (for local development)
            try:
                config.load_kube_config()
                self.v1_client = client.CoreV1Api()
                self.logger.info("Successfully connected to Kubernetes cluster using kubeconfig")
                return True
            except config.ConfigException as e:
                self.logger.error(f"Failed to load kubeconfig: {e}")
                return False
            except Exception as e:
                self.logger.error(f"Unexpected error loading kubeconfig: {e}")
                return False
        except Exception as e:
            self.logger.error(f"Unexpected error connecting to cluster: {e}")
            return False

    def get_containers_with_missing_limits(self, namespace: Optional[str] = None) -> List[ContainerLimitIssue]:
        """
        Fetch pods and identify containers with missing limits.

        Args:
            namespace: Optional namespace to filter pods. If None, checks all namespaces.

        Returns:
            List[ContainerLimitIssue]: List of containers with missing CPU or memory limits
        """
        containers_with_issues = []

        try:
            # Fetch pods from specific namespace or all namespaces
            if namespace:
                self.logger.info(f"Checking pods in namespace: {namespace}")
                pod_list = self.v1_client.list_namespaced_pod(namespace=namespace, watch=False)
            else:
                self.logger.info("Checking pods across all namespaces")
                pod_list = self.v1_client.list_pod_for_all_namespaces(watch=False)

            for pod in pod_list.items:
                namespace_name = pod.metadata.namespace
                pod_name = pod.metadata.name
                containers = pod.spec.containers

                # Check each container for missing limits
                for container in containers:
                    resources = container.resources
                    limits = resources.limits if resources else None

                    missing_cpu = limits is None or limits.get("cpu") is None
                    missing_memory = limits is None or limits.get("memory") is None

                    # Only add if at least one limit is missing
                    if missing_cpu or missing_memory:
                        issue = ContainerLimitIssue(
                            namespace=namespace_name,
                            pod_name=pod_name,
                            container_name=container.name,
                            missing_cpu_limit=missing_cpu,
                            missing_memory_limit=missing_memory,
                        )
                        containers_with_issues.append(issue)
                        self.logger.debug(
                            f"Found container with missing limits: {namespace_name}/{pod_name}/{container.name} "
                            f"(cpu: {missing_cpu}, memory: {missing_memory})"
                        )

            self.logger.info(
                f"Found {len(containers_with_issues)} container(s) with missing resource limits"
            )
            return containers_with_issues

        except ApiException as e:
            self.logger.error(f"Kubernetes API error: {e}")
            return []
        except Exception as e:
            self.logger.error(f"Unexpected error fetching pods: {e}")
            return []

    def annotate_pod(self, namespace: str, pod_name: str, missing_cpu: bool, missing_memory: bool) -> bool:
        """
        Add warning annotation to a pod based on missing resource limits.

        Args:
            namespace: The namespace of the pod
            pod_name: The name of the pod
            missing_cpu: Whether CPU limit is missing
            missing_memory: Whether memory limit is missing

        Returns:
            bool: True if annotation was successful, False otherwise
        """
        try:
            # Determine the appropriate annotation value
            if missing_cpu and missing_memory:
                annotation_value = "no-limits"
            elif missing_cpu:
                annotation_value = "no-cpu-limit"
            elif missing_memory:
                annotation_value = "no-memory-limit"
            else:
                self.logger.warning(f"No missing limits to annotate for {namespace}/{pod_name}")
                return False

            # Prepare the patch
            patch = {
                "metadata": {
                    "annotations": {
                        "warning": annotation_value
                    }
                }
            }

            # Apply the patch
            self.v1_client.patch_namespaced_pod(
                name=pod_name,
                namespace=namespace,
                body=patch
            )

            self.logger.info(
                f"Successfully annotated pod {namespace}/{pod_name} with warning={annotation_value}"
            )
            return True

        except ApiException as e:
            self.logger.error(
                f"Failed to annotate pod {namespace}/{pod_name}: {e.status} - {e.reason}"
            )
            return False
        except Exception as e:
            self.logger.error(
                f"Unexpected error annotating pod {namespace}/{pod_name}: {e}"
            )
            return False

    def annotate_pods_with_issues(self, issues: List[ContainerLimitIssue]) -> Tuple[int, int]:
        """
        Annotate all pods that have containers with missing limits.
        Groups issues by pod to avoid duplicate annotations.

        Args:
            issues: List of ContainerLimitIssue objects

        Returns:
            Tuple[int, int]: (number of successfully annotated pods, number of failed annotations)
        """
        # Group issues by pod (namespace + pod_name)
        pods_to_annotate = {}

        for issue in issues:
            pod_key = f"{issue.namespace}/{issue.pod_name}"

            if pod_key not in pods_to_annotate:
                pods_to_annotate[pod_key] = {
                    "namespace": issue.namespace,
                    "pod_name": issue.pod_name,
                    "missing_cpu": False,
                    "missing_memory": False
                }

            # Track if any container in this pod is missing CPU or memory limits
            if issue.missing_cpu_limit:
                pods_to_annotate[pod_key]["missing_cpu"] = True
            if issue.missing_memory_limit:
                pods_to_annotate[pod_key]["missing_memory"] = True

        # Annotate each pod
        success_count = 0
        failure_count = 0

        self.logger.info(f"Annotating {len(pods_to_annotate)} pod(s) with warning labels")

        for pod_info in pods_to_annotate.values():
            if self.annotate_pod(
                namespace=pod_info["namespace"],
                pod_name=pod_info["pod_name"],
                missing_cpu=pod_info["missing_cpu"],
                missing_memory=pod_info["missing_memory"]
            ):
                success_count += 1
            else:
                failure_count += 1

        return success_count, failure_count


class OutputFormatter:
    """Handles formatting output in different formats."""

    @staticmethod
    def format_table(issues: List[ContainerLimitIssue]) -> str:
        """
        Format issues as a human-readable table.

        Args:
            issues: List of ContainerLimitIssue objects

        Returns:
            str: Formatted table string
        """
        if not issues:
            return "No containers with missing resource limits found."

        # Calculate column widths
        headers = ["NAMESPACE", "POD NAME", "CONTAINER NAME", "MISSING CPU", "MISSING MEMORY"]
        col_widths = [
            max(len(headers[0]), max((len(issue.namespace) for issue in issues), default=0)),
            max(len(headers[1]), max((len(issue.pod_name) for issue in issues), default=0)),
            max(len(headers[2]), max((len(issue.container_name) for issue in issues), default=0)),
            len(headers[3]),
            len(headers[4]),
        ]

        # Build table
        lines = []
        separator = (
            "+" + "+".join("-" * (w + 2) for w in col_widths) + "+"
        )
        lines.append(separator)
        lines.append(
            "| "
            + " | ".join(
                f"{h:<{col_widths[i]}}" for i, h in enumerate(headers)
            )
            + " |"
        )
        lines.append(separator)

        for issue in issues:
            lines.append(
                "| "
                + " | ".join(
                    f"{val:<{col_widths[i]}}"
                    for i, val in enumerate(
                        [
                            issue.namespace,
                            issue.pod_name,
                            issue.container_name,
                            "YES" if issue.missing_cpu_limit else "NO",
                            "YES" if issue.missing_memory_limit else "NO",
                        ]
                    )
                )
                + " |"
            )

        lines.append(separator)
        return "\n".join(lines)

    @staticmethod
    def format_json(issues: List[ContainerLimitIssue]) -> str:
        """
        Format issues as JSON.

        Args:
            issues: List of ContainerLimitIssue objects

        Returns:
            str: JSON formatted string
        """
        return json.dumps([asdict(issue) for issue in issues], indent=2)

    @staticmethod
    def format_csv(issues: List[ContainerLimitIssue]) -> str:
        """
        Format issues as CSV.

        Args:
            issues: List of ContainerLimitIssue objects

        Returns:
            str: CSV formatted string
        """
        lines = ["NAMESPACE,POD_NAME,CONTAINER_NAME,MISSING_CPU_LIMIT,MISSING_MEMORY_LIMIT"]

        for issue in issues:
            lines.append(
                f'"{issue.namespace}","{issue.pod_name}","{issue.container_name}",'
                f'"{issue.missing_cpu_limit}","{issue.missing_memory_limit}"'
            )

        return "\n".join(lines)


def setup_logging(log_level: str) -> logging.Logger:
    """
    Configure logging for the application.

    Args:
        log_level: Logging level (DEBUG, INFO, WARNING, ERROR)

    Returns:
        logging.Logger: Configured logger instance
    """
    numeric_level = getattr(logging, log_level.upper(), logging.INFO)
    
    log_format = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    
    # Console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(logging.Formatter(log_format))
    
    # File handler (optional, for daemon/cron usage)
    log_dir = Path.home() / ".k8s_pod_checker"
    log_dir.mkdir(exist_ok=True)
    log_file = log_dir / "pod_checker.log"
    
    file_handler = logging.FileHandler(log_file)
    file_handler.setFormatter(logging.Formatter(log_format))
    
    logger = logging.getLogger("KubernetesPodChecker")
    logger.setLevel(numeric_level)
    logger.addHandler(console_handler)
    logger.addHandler(file_handler)
    
    return logger


def parse_arguments() -> argparse.Namespace:
    """
    Parse command-line arguments.

    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description="Check Kubernetes pods for missing resource limits. See README.md for detailed usage examples.",
    )

    parser.add_argument(
        "--output",
        choices=["table", "json", "csv"],
        default="table",
        help="Output format (default: table)",
    )

    parser.add_argument(
        "--log-level",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        default="INFO",
        help="Logging level (default: INFO)",
    )

    parser.add_argument(
        "--namespace",
        "-n",
        type=str,
        default=None,
        help="Check pods in a specific namespace. If not provided, checks all namespaces.",
    )

    parser.add_argument(
        "--annotate",
        action="store_true",
        default=os.getenv("ANNOTATE", "false").lower() == "true",
        help="Automatically annotate pods with warning labels based on missing limits. "
             "Annotations: 'warning: no-cpu-limit', 'warning: no-memory-limit', or 'warning: no-limits'. "
             "Can also be set via ANNOTATE environment variable (true/false).",
    )

    return parser.parse_args()


def main() -> int:
    """
    Main entry point for the script.

    Returns:
        int: Exit code (0 for success, 1 for failure)
    """
    args = parse_arguments()
    logger = setup_logging(args.log_level)

    logger.info("Starting Kubernetes Pod Resource Limits Checker")

    # Initialize and connect to cluster
    checker = KubernetesPodChecker(logger)
    if not checker.connect():
        logger.error("Failed to connect to Kubernetes cluster")
        return 1

    # Fetch containers with missing limits
    issues = checker.get_containers_with_missing_limits(namespace=args.namespace)

    # Annotate pods if requested
    if args.annotate and issues:
        logger.info("Annotation mode enabled - adding warning annotations to pods")
        success_count, failure_count = checker.annotate_pods_with_issues(issues)
        logger.info(
            f"Annotation results: {success_count} successful, {failure_count} failed"
        )
        if failure_count > 0:
            logger.warning(
                f"{failure_count} pod(s) could not be annotated. Check logs for details."
            )
    elif args.annotate and not issues:
        logger.info("No pods with missing limits found - nothing to annotate")

    # Format and output results
    formatter = OutputFormatter()
    if args.output == "json":
        output = formatter.format_json(issues)
    elif args.output == "csv":
        output = formatter.format_csv(issues)
    else:
        output = formatter.format_table(issues)

    print(output)

    logger.info("Kubernetes Pod Resource Limits Checker completed successfully")
    return 0


if __name__ == "__main__":
    sys.exit(main())