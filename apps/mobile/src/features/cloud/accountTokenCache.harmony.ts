import { deleteItemAsync, getItemAsync, setItemAsync } from "expo-secure-store";

export const tokenCache = {
  getToken: (key: string) => getItemAsync(key),
  saveToken: (key: string, token: string) => setItemAsync(key, token),
  clearToken: (key: string) => deleteItemAsync(key),
};
