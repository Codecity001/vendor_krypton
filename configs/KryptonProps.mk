# Copyright 2021 AOSP-Krypton Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Version and fingerprint
KRYPTON_VERSION_MAJOR := 1
KRYPTON_VERSION_MINOR := 0
KRYPTON_VERSION := v$(KRYPTON_VERSION_MAJOR).$(KRYPTON_VERSION_MINOR)

# Set props
PRODUCT_SYSTEM_DEFAULT_PROPERTIES += \
  ro.krypton.build.device=$(KRYPTON_BUILD) \
  ro.krypton.build.version=$(KRYPTON_VERSION)
