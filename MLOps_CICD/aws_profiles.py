class UserProfiles:
    def __init__(self, path="profiles.conf") -> None:
        self.profiles = {}
        with open(path, "r") as file:
            for line in file:
                key, value = line.strip().split("=")
                self.profiles[key.strip()] = int(value.strip())

    def list_profiles(self):
        return self.profiles.keys()

    def get_profile_id(self, profile_name: str) -> int:
        return self.profiles[profile_name]

    def get_profile_name(self, profile_id: int) -> str:
        for key, val in self.profiles.items():
            if val == profile_id:
                return key

        raise ValueError(f"Profile with id: '{profile_id}' not found")