import { cn } from "@/lib/utils";
import { ScrollArea } from "@/components/ui/scroll-area";
import { motion } from "framer-motion";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Link, useLocation } from "react-router-dom";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Separator } from "@/components/ui/separator";
import {
  ChevronsUpDown,
  LayoutDashboard,
  CheckSquare,
  Target,
  Smile,
  Wallet,
  Droplets,
  Moon,
  Settings,
  LogOut,
  UserCircle,
} from "lucide-react";

const sidebarVariants = {
  open: {
    width: "15rem",
  },
  closed: {
    width: "3.05rem",
  },
};

const contentVariants = {
  open: { display: "block", opacity: 1 },
  closed: { display: "block", opacity: 1 },
};

const variants = {
  open: {
    x: 0,
    opacity: 1,
    transition: {
      x: { stiffness: 1000, velocity: -100 },
    },
  },
  closed: {
    x: -20,
    opacity: 0,
    transition: {
      x: { stiffness: 100 },
    },
  },
};

const transitionProps = {
  type: "tween" as const,
  ease: "easeOut" as const,
  duration: 0.2,
  staggerChildren: 0.1,
};

const staggerVariants = {
  open: {
    transition: { staggerChildren: 0.03, delayChildren: 0.02 },
  },
};

const navItems = [
  { icon: LayoutDashboard, label: "Dashboard", path: "/" },
  { icon: CheckSquare, label: "Tasks", path: "/tasks" },
  { icon: Target, label: "Habits", path: "/habits" },
  { icon: Smile, label: "Mood", path: "/mood" },
  { icon: Wallet, label: "Expenses", path: "/expenses" },
  { icon: Droplets, label: "Water", path: "/water" },
  { icon: Moon, label: "Sleep", path: "/sleep" },
];

export function AnimatedSidebar() {
  const [isCollapsed, setIsCollapsed] = useState(true);
  const location = useLocation();
  const currentPath = location.pathname;

  const isActive = (path: string) => {
    if (path === "/") return currentPath === "/";
    return currentPath.startsWith(path);
  };

  return (
    <motion.div
      className={cn(
        "hidden md:block fixed left-0 z-40 h-full shrink-0 border-r border-sidebar-border bg-sidebar"
      )}
      initial={isCollapsed ? "closed" : "open"}
      animate={isCollapsed ? "closed" : "open"}
      variants={sidebarVariants}
      transition={transitionProps}
      onMouseEnter={() => setIsCollapsed(false)}
      onMouseLeave={() => setIsCollapsed(true)}
    >
      <motion.div
        className="relative z-40 flex text-muted-foreground h-full shrink-0 flex-col transition-all"
        variants={contentVariants}
      >
        <motion.ul variants={staggerVariants} className="flex h-full flex-col">
          <div className="flex grow flex-col items-center">
            {/* Header / Logo */}
            <div className="flex h-14 w-full shrink-0 border-b border-sidebar-border p-2">
              <div className="mt-[1.5px] flex w-full">
                <DropdownMenu modal={false}>
                  <DropdownMenuTrigger className="w-full" asChild>
                    <Button
                      variant="ghost"
                      size="sm"
                      className="flex w-fit items-center gap-2 px-2"
                    >
                      <Avatar className="rounded size-6 bg-primary text-primary-foreground">
                        <AvatarFallback className="text-xs bg-primary text-primary-foreground">B</AvatarFallback>
                      </Avatar>
                      <motion.li
                        variants={variants}
                        className="flex w-fit items-center gap-2 list-none"
                      >
                        {!isCollapsed && (
                          <>
                            <p className="text-sm font-semibold text-foreground">
                              BudgetBox
                            </p>
                            <ChevronsUpDown className="h-4 w-4 text-muted-foreground/50" />
                          </>
                        )}
                      </motion.li>
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="start">
                    <DropdownMenuItem asChild className="flex items-center gap-2">
                      <Link to="/settings">
                        <Settings className="h-4 w-4" /> Settings
                      </Link>
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
              </div>
            </div>

            {/* Navigation */}
            <div className="flex h-full w-full flex-col">
              <div className="flex grow flex-col gap-4">
                <ScrollArea className="h-16 grow p-2">
                  <div className={cn("flex w-full flex-col gap-1")}>
                    {navItems.map((item) => (
                      <Link
                        key={item.path}
                        to={item.path}
                        className={cn(
                          "flex h-8 w-full flex-row items-center rounded-md px-2 py-1.5 transition hover:bg-sidebar-accent hover:text-sidebar-accent-foreground",
                          isActive(item.path) && "bg-sidebar-accent text-primary"
                        )}
                      >
                        <item.icon className="h-4 w-4 shrink-0" />
                        <motion.li variants={variants} className="list-none">
                          {!isCollapsed && (
                            <p className="ml-2 text-sm font-medium">{item.label}</p>
                          )}
                        </motion.li>
                      </Link>
                    ))}
                  </div>
                </ScrollArea>
              </div>

              {/* Bottom section */}
              <div className="flex flex-col p-2 border-t border-sidebar-border">
                <Link
                  to="/settings"
                  className={cn(
                    "flex h-8 w-full flex-row items-center rounded-md px-2 py-1.5 transition hover:bg-sidebar-accent hover:text-sidebar-accent-foreground",
                    isActive("/settings") && "bg-sidebar-accent text-primary"
                  )}
                >
                  <Settings className="h-4 w-4 shrink-0" />
                  <motion.li variants={variants} className="list-none">
                    {!isCollapsed && (
                      <p className="ml-2 text-sm font-medium">Settings</p>
                    )}
                  </motion.li>
                </Link>
                <div>
                  <DropdownMenu modal={false}>
                    <DropdownMenuTrigger className="w-full">
                      <div className="flex h-8 w-full flex-row items-center gap-2 rounded-md px-2 py-1.5 transition hover:bg-sidebar-accent hover:text-sidebar-accent-foreground">
                        <Avatar className="size-4">
                          <AvatarFallback className="text-[10px]">U</AvatarFallback>
                        </Avatar>
                        <motion.li
                          variants={variants}
                          className="flex w-full items-center gap-2 list-none"
                        >
                          {!isCollapsed && (
                            <>
                              <p className="text-sm font-medium">Account</p>
                              <ChevronsUpDown className="ml-auto h-4 w-4 text-muted-foreground/50" />
                            </>
                          )}
                        </motion.li>
                      </div>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent sideOffset={5}>
                      <div className="flex flex-row items-center gap-2 p-2">
                        <Avatar className="size-6">
                          <AvatarFallback className="text-xs">U</AvatarFallback>
                        </Avatar>
                        <div className="flex flex-col text-left">
                          <span className="text-sm font-medium">User</span>
                          <span className="line-clamp-1 text-xs text-muted-foreground">
                            user@example.com
                          </span>
                        </div>
                      </div>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem asChild className="flex items-center gap-2">
                        <Link to="/settings">
                          <UserCircle className="h-4 w-4" /> Profile
                        </Link>
                      </DropdownMenuItem>
                      <DropdownMenuItem asChild className="flex items-center gap-2">
                        <Link to="/auth">
                          <LogOut className="h-4 w-4" /> Sign out
                        </Link>
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>
              </div>
            </div>
          </div>
        </motion.ul>
      </motion.div>
    </motion.div>
  );
}