import { useState } from "react";
import { useNavigate, Link } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Mail, Lock, User, ArrowRight, Eye, EyeOff, ArrowLeft } from "lucide-react";
import { useToast } from "@/hooks/use-toast";

import { login, register } from "@/api/auth.api";
import api from "@/api/axios";

export default function Auth() {
  const [isSignUp, setIsSignUp] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [formData, setFormData] = useState({
    name: "",
    email: "",
    password: "",
  });
  const navigate = useNavigate();
  const { toast } = useToast();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);

    try {
      if (isSignUp) {
        // 🔹 REGISTER
        await register(formData.email, formData.password);

        // 🔹 LOG IN so we have tokens to authorize the profile update
        const data = await login(formData.email, formData.password);
        localStorage.setItem("access_token", data.access_token);
        localStorage.setItem("refresh_token", data.refresh_token);

        // 🔹 SAVE FULL NAME to the profile (register/login don't accept it)
        const fullName = formData.name.trim();
        const [firstName, ...rest] = fullName.split(/\s+/).filter(Boolean);
        const lastName = rest.join(" ");

        try {
          // GET /profile first — it lazily creates the profile row, which
          // PUT /profile requires to already exist.
          await api.get("/profile");
          await api.put("/profile", {
            first_name: firstName || "",
            last_name: lastName || "",
            timezone: "UTC",
          });
        } catch (profileErr) {
          // Account + session are already created; don't block sign-up on
          // this best-effort profile update.
          console.warn("Failed to save profile name", profileErr);
        }

        toast({
          title: "Account created",
          description: "Welcome to BudgetBox!",
        });

        // Clear password field on successful login (security + UX)
        setFormData({ ...formData, password: "" });

        navigate("/dashboard");
      } else {
        // 🔹 LOGIN
        const data = await login(formData.email, formData.password);

        // 🔐 STORE TOKENS
        localStorage.setItem("access_token", data.access_token);
        localStorage.setItem("refresh_token", data.refresh_token);

        toast({
          title: "Welcome back",
          description: "You have been signed in successfully.",
        });

        // Clear password field on successful login (security + UX)
        setFormData({ ...formData, password: "" });

        // Redirect to main protected page
        navigate("/dashboard");
      }
    } catch (err: any) {
      toast({
        title: "Authentication failed",
        description:
          err?.response?.data?.detail || "Invalid email or password",
        variant: "destructive",
      });
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-background flex">
      {/* Left side - Form */}
      <div className="flex-1 flex items-center justify-center p-8 relative">
        {/* Back to Home Button */}
        <Link 
          to="/" 
          className="absolute top-6 left-6 flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors"
        >
          <ArrowLeft className="w-4 h-4" />
          Back to Home
        </Link>
        
        <div className="w-full max-w-sm space-y-8">
          {/* Logo */}
          <div className="text-center">
            <Link to="/" className="inline-block">
              <h1 className="text-2xl font-bold text-foreground tracking-tight">
                BudgetBox
              </h1>
            </Link>
            <p className="mt-2 text-sm text-muted-foreground">
              {isSignUp ? "Create your account" : "Welcome back"}
            </p>
          </div>

          {/* Form */}
          <form onSubmit={handleSubmit} className="space-y-5">
            {isSignUp && (
              <div className="space-y-2">
                <Label htmlFor="name" className="text-sm font-medium text-foreground">
                  Full Name
                </Label>
                <div className="relative">
                  <User className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                  <Input
                    id="name"
                    type="text"
                    placeholder="John Doe"
                    className="pl-10 h-11"
                    value={formData.name}
                    onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                    required
                  />
                </div>
              </div>
            )}

            <div className="space-y-2">
              <Label htmlFor="email" className="text-sm font-medium text-foreground">
                Email
              </Label>
              <div className="relative">
                <Mail className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                <Input
                  id="email"
                  type="email"
                  placeholder="you@example.com"
                  className="pl-10 h-11"
                  value={formData.email}
                  onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                  required
                />
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="password" className="text-sm font-medium text-foreground">
                Password
              </Label>
              <div className="relative">
                <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                <Input
                  id="password"
                  type={showPassword ? "text" : "password"}
                  placeholder="••••••••"
                  className="pl-10 pr-10 h-11"
                  value={formData.password}
                  onChange={(e) => setFormData({ ...formData, password: e.target.value })}
                  required
                  minLength={8}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground transition-colors"
                >
                  {showPassword ? (
                    <EyeOff className="w-4 h-4" />
                  ) : (
                    <Eye className="w-4 h-4" />
                  )}
                </button>
              </div>
            </div>

            {!isSignUp && (
              <div className="flex justify-end">
                <button
                  type="button"
                  className="text-sm text-muted-foreground hover:text-foreground transition-colors"
                >
                  Forgot password?
                </button>
              </div>
            )}

            <Button
              type="submit"
              className="w-full h-11 gap-2"
              disabled={isLoading}
            >
              {isLoading ? (
                <div className="w-4 h-4 border-2 border-primary-foreground/30 border-t-primary-foreground rounded-full animate-spin" />
              ) : (
                <>
                  {isSignUp ? "Create Account" : "Sign In"}
                  <ArrowRight className="w-4 h-4" />
                </>
              )}
            </Button>
          </form>

          {/* Toggle */}
          <div className="text-center">
            <p className="text-sm text-muted-foreground">
              {isSignUp ? "Already have an account?" : "Don't have an account?"}
              <button
                type="button"
                onClick={() => setIsSignUp(!isSignUp)}
                className="ml-1 font-medium text-foreground hover:text-primary transition-colors"
              >
                {isSignUp ? "Sign in" : "Sign up"}
              </button>
            </p>
          </div>
        </div>
      </div>

      {/* Right side - Decorative */}
      <div className="hidden lg:flex flex-1 bg-muted items-center justify-center p-12">
        <div className="max-w-md space-y-6 text-center">
          <div className="w-20 h-20 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto">
            <div className="w-10 h-10 rounded-lg bg-primary" />
          </div>
          <h2 className="text-2xl font-semibold text-foreground">
            Track everything that matters
          </h2>
          <p className="text-muted-foreground leading-relaxed">
            Manage your tasks, habits, mood, expenses, water intake, and sleep patterns all in one beautiful, minimal dashboard.
          </p>
          <div className="flex justify-center gap-8 pt-4">
            <div className="text-center">
              <p className="text-2xl font-bold text-foreground">6</p>
              <p className="text-xs text-muted-foreground">Trackers</p>
            </div>
            <div className="text-center">
              <p className="text-2xl font-bold text-foreground">∞</p>
              <p className="text-xs text-muted-foreground">Entries</p>
            </div>
            <div className="text-center">
              <p className="text-2xl font-bold text-foreground">0</p>
              <p className="text-xs text-muted-foreground">Ads</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}